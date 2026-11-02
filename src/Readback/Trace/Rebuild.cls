/// Rebuilds a decision from its trace record alone: the stored floor and agent facts go back through the
/// composer, and the answer is what the record says the decision was. Reads no other table.
Class Readback.Trace.Rebuild
{

/// Returns {"ok":true,"finalSeverity","route","reason","divergence"} or {"ok":false,"error":"..."} when the
/// record lacks a field the composer needs.
ClassMethod Explain(pTraceId As %Integer) As %DynamicObject
{
	Set tTrace = ##class(Readback.Trace.Decision).%OpenId(pTraceId)
	If '$IsObject(tTrace) { Quit {"ok":false,"error":"no trace record with that id"} }
	Quit ..ExplainRecord(tTrace)
}

ClassMethod ExplainRecord(pTrace As Readback.Trace.Decision) As %DynamicObject
{
	Set tMissing = ""
	For tName = "FloorSeverity", "FinalSeverity", "Route" {
		If $Property(pTrace, tName) = "" { Set tMissing = tMissing_$Select(tMissing="":"", 1:", ")_tName }
	}
	If pTrace.SchemaValid && ((pTrace.AgentDecision = "") || (pTrace.AgentSeverity = "")) {
		Set tMissing = tMissing_$Select(tMissing="":"", 1:", ")_"AgentDecision or AgentSeverity of a valid answer"
	}
	If tMissing '= "" { Quit {"ok":false,"error":("the record cannot be rebuilt, missing: "_tMissing)} }
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pTrace.FloorSeverity, tFloor.RuleId = pTrace.FloorRuleId, tFloor.Note = pTrace.FloorNote
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = pTrace.SchemaValid
	Set tAgent.Decision = pTrace.AgentDecision, tAgent.Severity = pTrace.AgentSeverity, tAgent.Confidence = pTrace.AgentConfidence
	Set tAgent.FailureKind = pTrace.FailureKind, tAgent.FailureReason = pTrace.FailureReason
	Set tFinal = ##class(Readback.Triage.Composer).Compose(tFloor, tAgent)
	Set tOut = {"ok":true,"finalSeverity":(tFinal.FinalSeverity),"route":(tFinal.Route),"reason":(tFinal.Reason),"divergence":(tFinal.Divergence)}
	Set tOut.rounds = +pTrace.Rounds, tOut.policyRefusal = pTrace.PolicyRefusal, tOut.evidenceCheck = pTrace.EvidenceCheck
	Set tOut.toolCalls = ..CallsOf(pTrace)
	Quit tOut
}


/// The tool calls of a decision in order, read from the trace table.
ClassMethod CallsOf(pTrace As Readback.Trace.Decision) As %DynamicArray
{
	Set tList = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Seq, Tool, ArgumentsJson, ResultJson, Status, Reason, DurationMs FROM Readback_Trace.ToolCall WHERE Decision = ? ORDER BY Seq", pTrace.%Id())
	While tRS.%Next() {
		Do tList.%Push({"seq":(tRS.%Get("Seq")),"tool":(tRS.%Get("Tool")),"arguments":(tRS.%Get("ArgumentsJson")),"result":(tRS.%Get("ResultJson")),"status":(tRS.%Get("Status")),"reason":(tRS.%Get("Reason")),"durationMs":(+tRS.%Get("DurationMs"))})
	}
	Quit tList
}

}
