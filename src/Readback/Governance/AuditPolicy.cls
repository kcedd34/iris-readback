/// The audit policy of the agent's tool set: one entry for every tool call, executed or refused, in the order the
/// agent made them, and one message per call so the call is a step of the session in the visual trace. The entries
/// are kept in the operation's process; the operation merges them with the session history after the call.
/// An error inside a policy is swallowed silently by the platform (docs/probes.md), so every path here catches its
/// own error, writes it to the event log and counts it, and never throws.
Class Readback.Governance.AuditPolicy Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
	Try {
		Set tOk = $System.Status.IsOK(status)
		Set tResult = $Select($IsObject(result) && tOk:result.%Get("result_json"), 1:"")
		Set tReason = $Select(tOk:"", 1:##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(status)))
		Do ##class(Readback.Governance.AuditPolicy).Record(call, $Select(tOk:"ok", 1:"failed"), tResult, tReason, duration)
	} Catch ex {
		Do ##class(Readback.Governance.AuditPolicy).Fault(ex)
	}
	Quit $$$OK
}

Method %LogDenial(call As %DynamicObject, metadata As %DynamicObject, status As %Status) As %Status
{
	Try {
		Do ##class(Readback.Governance.AuditPolicy).Record(call, "refused", "", ##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(status)), 0)
	} Catch ex {
		Do ##class(Readback.Governance.AuditPolicy).Fault(ex)
	}
	Quit $$$OK
}

/// Adds one entry for a call. The arguments reach an audit policy as a JSON string, not as an object.
ClassMethod Record(pCall As %DynamicObject, pStatus As %String, pResult As %String, pReason As %String, pDuration As %Integer)
{
	Set tArgs = pCall.arguments
	If $IsObject(tArgs) { Set tArgs = tArgs.%ToJSON() }
	Set tSeq = $Increment(^||Readback.AuditSeq)
	Set tEntry = {"seq":(tSeq),"tool":(pCall.name),"arguments":(tArgs),"status":(pStatus),"reason":($Extract(pReason, 1, 300)),"durationMs":(+pDuration)}
	Set ^||Readback.AuditLog(tSeq) = tEntry.%ToJSON()
	Do ..Emit(tSeq, pCall.name, pStatus, +pDuration, ##class(Readback.Tools.Summary).Of(pCall.name, pStatus, pResult, pReason))
}

/// Sends the visual trace message through the host the operation left for this call, when there is one.
ClassMethod Emit(pSeq As %Integer, pTool As %String, pStatus As %String, pDuration As %Integer, pSummary As %String)
{
	Quit:'$IsObject($Get(%ReadbackHost))
	Set tMsg = ##class(Readback.Msg.ToolCall).%New()
	Set tMsg.CaseId = ##class(Readback.Tools.Binding).Get("caseId"), tMsg.Seq = pSeq, tMsg.Tool = pTool
	Set tMsg.Status = pStatus, tMsg.DurationMs = pDuration, tMsg.Summary = pSummary
	Set tSC = %ReadbackHost.SendRequestAsync("Readback.Agent.ToolHost", tMsg, 0)
	If $System.Status.IsError(tSC) { Do ##class(Readback.Governance.AuditPolicy).Fault($System.Status.GetErrorText(tSC)) }
}

/// An error inside this policy: counted for the operation and written to the event log, never raised.
ClassMethod Fault(pWhat)
{
	Set ^||Readback.AuditFaults = $Get(^||Readback.AuditFaults) + 1
	Set tText = $Select($IsObject(pWhat):pWhat.Name_" "_$Extract(pWhat.Data, 1, 200), 1:$Extract(pWhat, 1, 300))
	Do ##class(%SYS.System).WriteToConsoleLog("Readback audit policy: "_##class(Readback.Config.Mode).Redact(tText), 0, 1)
}

/// The entries recorded in this process, in order, as a list of objects.
ClassMethod Entries() As %DynamicArray
{
	Set tList = []
	Set tSeq = ""
	For {
		Set tSeq = $Order(^||Readback.AuditLog(tSeq))
		Quit:tSeq=""
		Do tList.%Push({}.%FromJSON(^||Readback.AuditLog(tSeq)))
	}
	Quit tList
}

/// Forgets what this process recorded (start and end of a call).
ClassMethod Reset()
{
	Kill ^||Readback.AuditLog, ^||Readback.AuditSeq, ^||Readback.AuditFaults, ^||Readback.ScopeCalls
}

}
