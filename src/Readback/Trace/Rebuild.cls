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
	Quit {"ok":true,"finalSeverity":(tFinal.FinalSeverity),"route":(tFinal.Route),"reason":(tFinal.Reason),"divergence":(tFinal.Divergence)}
}

}
