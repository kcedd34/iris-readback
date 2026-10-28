/// Turns what the agent step returned into a final decision. Holds no severity or routing logic:
/// it classifies the outcome, parses it, and hands the result to the composer.
Class Readback.Triage.Pipeline
{

/// pAgent returns the parsed or failed agent answer for the trace.
ClassMethod Decide(pLab As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult, pOutcome As Readback.Triage.AgentOutcome, Output pAgent As Readback.Triage.AgentOutput) As Readback.Triage.FinalDecision
{
	Set pAgent = ..Classify(pOutcome)
	// A rule that cannot judge the unit sends the case to a human unless the floor is already critical.
	If pFloor.UnitUnknown && (pFloor.Severity < 3) && pAgent.Valid && (pAgent.FailureKind = "") && (pAgent.Severity < 3) {
		Set pAgent.FailureKind = "unit-not-in-rule-table", pAgent.FailureReason = ..UnitReason(pOutcome.ConversionOutcome)
	}
	Quit ##class(Readback.Triage.Composer).Compose(pFloor, pAgent)
}

/// The agent answer for an outcome: a call failure becomes a failure kind, otherwise the text is parsed.
ClassMethod Classify(pOutcome As Readback.Triage.AgentOutcome) As Readback.Triage.AgentOutput
{
	If 'pOutcome.AgentCalled {
		// A retrieval that failed is not "nothing found": the agent is not asked to decide without its policy.
		If pOutcome.RetrievalFailed && (pOutcome.BudgetState = "ok") { Quit ..Failed("retrieval-unavailable", "retrieval unavailable") }
		Quit ..Failed("budget-reached", "budget reached: "_$Select(pOutcome.BudgetState="result-ceiling":"result ceiling", 1:"hourly ceiling"))
	}
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
