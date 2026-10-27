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
	Set tO.Content = "{""decision"":""CRITICAL"",""severity"":3,""rationale"":""big drop"",""evidence"":[""earlier-result""],""confidence"":""high""}"
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent)
	Do $$$AssertEquals(tAgent.Valid, 1, "valid")
	Do $$$AssertEquals(tFinal.Route, "readback", "the agent raise opens a read-back")
	Do $$$AssertEquals(tFinal.FinalSeverity, 3, "final severity 3")
}

}
