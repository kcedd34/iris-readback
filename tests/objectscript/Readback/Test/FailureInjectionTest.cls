/// P-3: every failure kind goes to a human with the literal reason, and never to an automatic decision.
Class Readback.Test.FailureInjectionTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Floor(pSeverity As %Integer, pUnitUnknown As %Boolean = 0) As Readback.Triage.FloorResult
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pSeverity, tFloor.UnitUnknown = pUnitUnknown
	Quit tFloor
}

ClassMethod Outcome(pKind As %String, pN As %Integer) As Readback.Triage.AgentOutcome
{
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Mode = "live", tO.LatencyMs = 10 + pN
	If pKind = "schema-invalid" {
		Set tO.Content = "{""decision"":""BOGUS"",""severity"":"_pN_",""rationale"":""r"",""evidence"":[],""confidence"":""high""}"
	} ElseIf pKind = "empty-or-refused" {
		Set tO.Content = $Select(pN#2:"", 1:"   ")
	} ElseIf pKind = "timeout" {
		Set tO.Status = $System.Status.Error(5001, "request timed out"), tO.TimedOut = 1, tO.TimeoutSeconds = 30
	} ElseIf pKind = "provider-error" {
		Set tO.Status = $System.Status.Error(5001, "<%AICore>ProviderError: Provider 'openai' error: API error: [server_error] failure number "_pN)
	} ElseIf pKind = "low-confidence" {
		Set tO.Content = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""unsure"",""evidence"":[],""confidence"":""low""}"
	} ElseIf pKind = "no-recorded-answer" {
		Set tO.Status = $System.Status.Error(5001, "no recorded answer")
	}
	Quit tO
}

Method TestEveryFailureKindTenTimesWithAndWithoutACriticalFloor()
{
	Set tKinds = $ListBuild("schema-invalid", "empty-or-refused", "timeout", "provider-error", "low-confidence", "no-recorded-answer")
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tPtr = 0
	While $ListNext(tKinds, tPtr, tKind) {
		For n = 1:1:10 {
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome(tKind, n), .tAgent)
			Do $$$AssertEquals(tAgent.FailureKind, tKind, tKind_" #"_n_": classified")
			Do $$$AssertEquals(tFinal.Route, "review", tKind_" #"_n_": floor 0 goes to review")
			Do $$$AssertTrue(tFinal.Reason'="", tKind_" #"_n_": literal reason present")
			Do $$$AssertTrue(tFinal.FinalSeverity '> 0 || (tAgent.Severity > 0), tKind_" #"_n_": no severity invented")
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), ..Outcome(tKind, n), .tAgent)
			Do $$$AssertEquals(tFinal.Route, "readback", tKind_" #"_n_": floor 3 goes to read-back")
			Do $$$AssertTrue(tFinal.FinalSeverity >= 3, tKind_" #"_n_": floor 3 stays critical")
		}
	}
}

Method TestLiteralReasons()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome("provider-error", 7), .tAgent)
	Do $$$AssertTrue(tAgent.FailureReason["ProviderError", "the provider's error text is kept")
	Do $$$AssertTrue(tAgent.FailureReason["failure number 7", "with its detail")
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome("timeout", 1), .tAgent)
	Do $$$AssertEquals(tAgent.FailureReason, "no answer within 30 seconds", "timeout reason names the limit")
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome("no-recorded-answer", 1), .tAgent)
	Do $$$AssertEquals(tAgent.FailureReason, "no recorded answer", "no-recorded-answer reason")
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome("empty-or-refused", 1), .tAgent)
	Do $$$AssertEquals(tAgent.FailureReason, "empty answer (refusal or no content)", "empty reason")
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), ..Outcome("low-confidence", 1), .tAgent)
	Do $$$AssertEquals(tAgent.FailureReason, "agent confidence low", "low-confidence reason")
}

Method TestInvalidTextIsKeptForTheTrace()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Content = "this is not json"
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.FailureKind, "schema-invalid", "classified as schema-invalid")
	Do $$$AssertEquals(tO.Content, "this is not json", "the raw text stays on the outcome for the trace")
	Do $$$AssertEquals(tFinal.Route, "review", "and the case goes to review")
}

Method TestUnitNotInRuleTableGoesToReview()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Content = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""fine"",""evidence"":[],""confidence"":""high""}"
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0, 1), tO, .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "an unknown unit with a calm agent goes to review")
	Do $$$AssertEquals(tFinal.Reason, "unit not in rule table", "with the fixed reason")
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3, 1), tO, .tAgent)
	Do $$$AssertEquals(tFinal.Route, "readback", "an unknown unit whose value is critical under a known unit still goes to read-back")
}

Method TestAValidAnswerFlowsThrough()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Content = "{""decision"":""CRITICAL"",""severity"":3,""rationale"":""big drop"",""evidence"":[""current-result"",""earlier-result-1""],""confidence"":""high""}"
	Set tO.ToolCallsJson = ..HistoryCall()
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.Valid, 1, "valid")
	Do $$$AssertEquals(tAgent.EvidenceCheck, "ok", "every cited identifier was returned by a tool")
	Do $$$AssertEquals(tFinal.Route, "readback", "the agent raise opens a read-back")
	Do $$$AssertEquals(tFinal.FinalSeverity, 3, "final severity 3")
}

/// The history tool's call as the operation records it: one result that carries the identifier earlier-result-1.
ClassMethod HistoryCall() As %String
{
	Quit "[{""seq"":1,""tool"":""get_patient_history"",""arguments"":""{}"",""result"":""{\""found\"":1,\""earlier\"":[{\""id\"":\""earlier-result-1\"",\""value\"":\""12.4\""}]}"",""status"":""ok"",""reason"":""""}]"
}

Method TestEvidenceNoToolReturnedIsInvalid()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Content = "{""decision"":""CRITICAL"",""severity"":3,""rationale"":""big drop"",""evidence"":[""earlier-result-1""],""confidence"":""high""}"
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.Valid, 0, "an identifier no tool returned makes the answer invalid")
	Do $$$AssertEquals(tAgent.FailureKind, "evidence-not-from-tools", "with its own failure kind")
	Do $$$AssertEquals(tAgent.EvidenceCheck, "not-from-tools", "and the check says so")
	Do $$$AssertEquals(tFinal.Route, "review", "a case with a floor of 0 goes to a person")
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
	Do $$$AssertEquals(tFinal.Route, "readback", "and a critical floor still reaches the read-back")
	Set tO.ToolCallsJson = ..HistoryCall()
	Set tO.Content = "{""decision"":""CRITICAL"",""severity"":3,""rationale"":""big drop"",""evidence"":[""earlier-result-2""],""confidence"":""high""}"
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.Valid, 0, "an identifier the tool did not return (earlier-result-2) is invalid even when a tool ran")
}

Method TestBudgetReachedTenTimesBothCeilings()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	For tState = "result-ceiling", "hourly-ceiling" {
		For n = 1:1:10 {
			Set tO = ##class(Readback.Triage.AgentOutcome).%New()
			Set tO.AgentCalled = 0, tO.BudgetState = tState, tO.Mode = "live"
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
			Do $$$AssertEquals(tAgent.FailureKind, "budget-reached", tState_" #"_n_": classified")
			Do $$$AssertEquals(tFinal.Route, "review", tState_" #"_n_": floor 0 goes to review")
			Do $$$AssertEquals(tFinal.Reason, "budget reached: "_$Select(tState="result-ceiling":"result ceiling", 1:"hourly ceiling"), tState_" #"_n_": literal reason")
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
			Do $$$AssertEquals(tFinal.Route, "readback", tState_" #"_n_": floor 3 still goes to read-back")
			Do $$$AssertEquals(tFinal.FinalSeverity, 3, tState_" #"_n_": floor 3 stays critical")
		}
	}
}

Method TestUnitReasonsFollowTheConversionOutcome()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tOk = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""fine"",""evidence"":[],""confidence"":""high""}"
	For tCase = $ListBuild("not-convertible", "unit not convertible"), $ListBuild("unavailable", "unit conversion unavailable"), $ListBuild("", "unit not in rule table") {
		Set tO = ##class(Readback.Triage.AgentOutcome).%New()
		Set tO.Content = tOk, tO.ConversionOutcome = $List(tCase, 1)
		Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0, 1), tO, .tAgent)
		Do $$$AssertEquals(tFinal.Route, "review", "an unjudged unit goes to review ("_$List(tCase, 1)_")")
		Do $$$AssertEquals(tFinal.Reason, $List(tCase, 2), "with the fixed reason")
		Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3, 1), tO, .tAgent)
		Do $$$AssertEquals(tFinal.Route, "readback", "a value critical under a known unit still goes to read-back ("_$List(tCase, 1)_")")
	}
}

Method TestRetrievalFailureGoesToAPersonAndIsNeverNothingFound()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	For n = 1:1:10 {
		Set tO = ##class(Readback.Triage.AgentOutcome).%New()
		Set tO.AgentCalled = 0, tO.RetrievalFailed = 1, tO.RetrievalNote = "the embedding model is not in the cache directory", tO.Mode = "live"
		Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
		Do $$$AssertEquals(tAgent.FailureKind, "retrieval-unavailable", "#"_n_": classified as a retrieval failure")
		Do $$$AssertEquals(tFinal.Route, "review", "#"_n_": floor 0 goes to review")
		Do $$$AssertEquals(tFinal.Reason, "retrieval unavailable", "#"_n_": with the fixed reason")
		Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
		Do $$$AssertEquals(tFinal.Route, "readback", "#"_n_": a rule-critical result still goes to read-back")
		Do $$$AssertEquals(tFinal.FinalSeverity, 3, "#"_n_": and stays critical")
	}
	// A reached budget outranks the retrieval reason when both apply.
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.AgentCalled = 0, tO.RetrievalFailed = 1, tO.BudgetState = "hourly-ceiling", tO.Mode = "live"
	Do ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.FailureKind, "budget-reached", "the budget reason is kept when the ceiling was the cause")
}

}
