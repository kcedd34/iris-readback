/// The only producer of a Readback.Triage.FinalDecision.
/// Final severity is the maximum of the floor and the agent, so the agent can raise a result and never lower it.
/// Routing follows the ordered table of the composition contract (first matching row wins).
Class Readback.Triage.Composer
{

/// pAgent may be empty. A usable answer has Valid true; a failure kind may still be set for
/// low confidence, where the answer is valid but must go to a human.
ClassMethod Compose(pFloor As Readback.Triage.FloorResult, pAgent As Readback.Triage.AgentOutput = "") As Readback.Triage.FinalDecision
{
	Set tFinal = ##class(Readback.Triage.FinalDecision).%New()
	Set tFloor = pFloor.Severity
	Set tUse = $IsObject(pAgent) && pAgent.Valid
	Set tFailed = '$IsObject(pAgent) || (pAgent.FailureKind '= "")
	Set tFinal.Floor = tFloor
	If tUse {
		Set tFinal.AgentSeverity = pAgent.Severity, tFinal.AgentDecision = pAgent.Decision
		Set tAgentSeverity = pAgent.Severity
	} Else {
		Set tAgentSeverity = 0
	}
	Set tFinal.FinalSeverity = $Select(tFloor>tAgentSeverity:tFloor, 1:tAgentSeverity)
	Set tFinal.Divergence = ..Divergence(tFloor, pAgent, tUse)

	Set tReasonFailure = $Select($IsObject(pAgent) && (pAgent.FailureReason'=""):pAgent.FailureReason, 1:"no usable agent answer")
	Set tDecision = $Select(tUse:pAgent.Decision, 1:"")
	If tFinal.FinalSeverity = 3 {
		Set tFinal.Route = "readback"
		Set tFinal.Reason = $Select(tFloor=3:"critical by rule", 1:"critical by the agent")
		If tFailed && tFloor = 3 { Set tFinal.Reason = tFinal.Reason_"; agent answer not used: "_tReasonFailure }
	} ElseIf tFailed && 'tUse {
		Set tFinal.Route = "review", tFinal.Reason = tReasonFailure
	} ElseIf (tDecision = "CRITICAL") && (tAgentSeverity < 3) {
		Set tFinal.Route = "review", tFinal.Reason = "agent decided CRITICAL with severity below 3"
	} ElseIf (tFinal.FinalSeverity = 1) || (tFinal.FinalSeverity = 2) {
		Set tFinal.Route = "review", tFinal.Reason = "agent raised the severity to "_tFinal.FinalSeverity_", not released automatically"
	} ElseIf tDecision = "NEEDS_REVIEW" {
		Set tFinal.Route = "review", tFinal.Reason = "agent asked for human review"
	} ElseIf tFailed {
		Set tFinal.Route = "review", tFinal.Reason = tReasonFailure
	} ElseIf (tDecision = "RECOLLECT") && (tFloor < 3) {
		Set tFinal.Route = "recollect", tFinal.Reason = "recollect requested because of sample quality"
	} ElseIf (tFinal.FinalSeverity = 0) && (tDecision = "NON_CRITICAL") {
		Set tFinal.Route = "release", tFinal.Reason = "not critical by rule or by the agent"
	} Else {
		Set tFinal.Route = "review", tFinal.Reason = "combination not covered by the routing table, sent to a human"
	}
	Quit tFinal
}

/// Text describing a disagreement between floor and agent, or empty.
ClassMethod Divergence(pFloor As %Integer, pAgent As Readback.Triage.AgentOutput, pUse As %Boolean) As %String
{
	Quit:'pUse ""
	Set tText = ""
	If pFloor = 3 {
		If pAgent.Severity < 3 { Set tText = "agent severity "_pAgent.Severity_" is below the rule floor 3" }
		If pAgent.Decision '= "CRITICAL" { Set tText = tText_$Select(tText="":"", 1:"; ")_"agent decision "_pAgent.Decision_" while the rule floor is critical" }
	}
	If (pAgent.Decision = "NON_CRITICAL") && (pAgent.Severity > 0) { Set tText = tText_$Select(tText="":"", 1:"; ")_"agent decision NON_CRITICAL contradicts its severity "_pAgent.Severity }
	If (pAgent.Decision = "CRITICAL") && (pAgent.Severity < 3) { Set tText = tText_$Select(tText="":"", 1:"; ")_"agent decision CRITICAL contradicts its severity "_pAgent.Severity }
	Quit tText
}

}
