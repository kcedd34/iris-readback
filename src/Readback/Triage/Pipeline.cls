/// Turns what the agent step returned into a final decision. Holds no severity or routing logic:
/// it classifies the outcome, parses it, and hands the result to the composer.
Class Readback.Triage.Pipeline
{

/// pAgent returns the parsed or failed agent answer for the trace.
ClassMethod Decide(pLab As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult, pOutcome As Readback.Triage.AgentOutcome, Output pAgent As Readback.Triage.AgentOutput) As Readback.Triage.FinalDecision
{
	Set pAgent = ..Classify(pOutcome)
	Do ..Govern(pFloor, pOutcome, pAgent)
	// A rule that cannot judge the unit sends the case to a human unless the floor is already critical.
	If pFloor.UnitUnknown && (pFloor.Severity < 3) && pAgent.Valid && (pAgent.FailureKind = "") && (pAgent.Severity < 3) {
		Set pAgent.FailureKind = "unit-not-in-rule-table", pAgent.FailureReason = ..UnitReason(pOutcome.ConversionOutcome)
	}
	Quit ##class(Readback.Triage.Composer).Compose(pFloor, pAgent)
}

/// The two checks that sit between the answer and the composition. First the evidence rule: every identifier the answer
/// cites must have been returned by a tool of this investigation, else the answer is handled as an invalid one. Then the
/// floor policy: an answer that would lower a critical floor is refused formally and the refusal is recorded. The
/// composition runs afterwards and does not depend on either.
ClassMethod Govern(pFloor As Readback.Triage.FloorResult, pOutcome As Readback.Triage.AgentOutcome, pAgent As Readback.Triage.AgentOutput) [ Private ]
{
	Quit:'pAgent.Valid
	Set tCalls = $Select(pOutcome.ToolCallsJson'="":[].%FromJSON(pOutcome.ToolCallsJson), 1:[])
	Set tBad = ##class(Readback.Governance.Evidence).Unsupported(pAgent.Evidence, tCalls)
	If tBad '= "" {
		Set pAgent.EvidenceCheck = "not-from-tools"
		Set pAgent.Valid = 0, pAgent.FailureKind = "evidence-not-from-tools"
		Set pAgent.FailureReason = $Extract("the answer cites evidence that no tool returned: "_tBad, 1, 500)
		Quit
	}
	Set pAgent.EvidenceCheck = "ok"
	Set tRefusal = ##class(Readback.Governance.FloorPolicy).Review(pFloor, pAgent)
	If tRefusal '= "" {
		Set pAgent.PolicyRefusal = $Extract(tRefusal, 1, 300)
		If pAgent.FailureKind = "" { Set pAgent.FailureKind = "floor-policy-refusal", pAgent.FailureReason = pAgent.PolicyRefusal }
	}
}

/// The agent answer for an outcome: a call failure becomes a failure kind, otherwise the text is parsed.
ClassMethod Classify(pOutcome As Readback.Triage.AgentOutcome) As Readback.Triage.AgentOutput
{
	If 'pOutcome.AgentCalled {
		// A retrieval that failed is not "nothing found": the agent is not asked to decide without its policy.
		If pOutcome.RetrievalFailed && (pOutcome.BudgetState = "ok") { Quit ..Failed("retrieval-unavailable", "retrieval unavailable") }
		Quit ..Failed("budget-reached", "budget reached: "_$Select(pOutcome.BudgetState="result-ceiling":"result ceiling", 1:"hourly ceiling"))
	}
	// The investigation itself failed (a tool failed, was refused or does not exist, or the rounds ran out): the answer,
	// if there is one, was reached with information missing and is not used.
	If pOutcome.ToolFailureKind '= "" { Quit ..Failed(pOutcome.ToolFailureKind, pOutcome.ToolFailureReason) }
	If pOutcome.TimedOut {
		Quit ..Failed("timeout", "no answer within "_pOutcome.TimeoutSeconds_" seconds")
	}
	If $System.Status.IsError(pOutcome.Status) {
		Set tText = $System.Status.GetErrorText(pOutcome.Status)
		If tText [ "no recorded answer" { Quit ..Failed("no-recorded-answer", "no recorded answer") }
		Quit ..Failed("provider-error", tText)
	}
	Quit ##class(Readback.Triage.AgentOutput).Parse(pOutcome.Content)
}

/// The fixed reason for a unit the rule table cannot judge, by what the conversion said.
ClassMethod UnitReason(pConversionOutcome As %String) As %String
{
	Quit $Case(pConversionOutcome, "not-convertible":"unit not convertible", "unavailable":"unit conversion unavailable", :"unit not in rule table")
}

ClassMethod Failed(pKind As %String, pReason As %String) As Readback.Triage.AgentOutput [ Private ]
{
	Set tOut = ##class(Readback.Triage.AgentOutput).%New()
	Set tOut.Valid = 0, tOut.FailureKind = pKind, tOut.FailureReason = pReason
	Quit tOut
}

}
