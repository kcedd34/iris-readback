/// The release guard: nothing uncertain is released automatically, and the agent cannot release against it. Tested on the effect:
/// a calm NON_CRITICAL answer is run through the pipeline for each case the guard holds, and for the cases it lets pass.
Class Readback.Test.ReleaseGuardTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Lab(pAnalyte As %String, pValue As %Numeric, pUnit As %String, pIndex As %String = "") As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.AnalyteCode = pAnalyte, tLab.ValueNumeric = pValue, tLab.ValueText = pValue, tLab.Unit = pUnit
	Do:pIndex'="" tLab.SampleIndices.Insert(pIndex)
	Quit tLab
}

ClassMethod Floor(pSeverity As %Integer) As Readback.Triage.FloorResult
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pSeverity
	Quit tFloor
}

/// A calm, confident, valid answer: the agent says the result is not critical.
ClassMethod Calm() As Readback.Triage.AgentOutcome
{
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Mode = "live", tO.LatencyMs = 10
	Set tO.Content = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""the value is normal"",""evidence"":[""current-result""],""confidence"":""high""}"
	Quit tO
}

Method Run(pLab As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult, Output pAgent As Readback.Triage.AgentOutput) As Readback.Triage.FinalDecision
{
	Quit ##class(Readback.Triage.Pipeline).Decide(pLab, pFloor, ..Calm(), .pAgent, pLab)
}

Method TestAControlWithACalmAnswerIsReleased()
{
	Set tFinal = ..Run(..Lab("2823-3", 4.1, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "release", "a normal value, no indices, floor zero: released")
	Set tFinal = ..Run(..Lab("2823-3", 4.1, "mmol/L", "HEMOLYSIS_INDEX=100"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "release", "an index at the limit of the policy is within it (the policy says above 100)")
	Set tFinal = ..Run(..Lab("2823-3", 6.0, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "release", "6.0 is below the borderline band (93 percent of 6.5 is 6.045)")
}

Method TestASampleOutsideThePolicyIsHeldForAPerson()
{
	Set tFinal = ..Run(..Lab("2823-3", 5.8, "mmol/L", "HEMOLYSIS_INDEX=151"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "a calm answer on a hemolyzed sample is not released")
	Do $$$AssertEquals(tAgent.FailureKind, "release-guard", "the hold is recorded as the release guard")
	Do $$$AssertTrue(tFinal.Reason [ "sample quality outside the policy", "the reason says why: "_tFinal.Reason)
	Do $$$AssertTrue(tFinal.Reason [ "HEMOLYSIS_INDEX 151 is above 100", "and names the index and the limit")
	Set tFinal = ..Run(..Lab("2823-3", 4.1, "mmol/L", "HEMOLYSIS_INDEX=abc"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "an index that is not a number is held too")
}

Method TestABorderlineValueIsHeldForAPerson()
{
	Set tFinal = ..Run(..Lab("2823-3", 6.3, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "potassium 6.3 is near the critical limit 6.5")
	Do $$$AssertTrue(tFinal.Reason [ "borderline band", "the reason says it is the borderline band: "_tFinal.Reason)
	Set tFinal = ..Run(..Lab("2823-3", 6.05, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "the band starts at 93 percent of the limit")
	Set tFinal = ..Run(..Lab("2951-2", 125, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "sodium 125 is near the critical low limit 120")
	Set tFinal = ..Run(..Lab("2951-2", 140, "mmol/L"), ..Floor(0), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "release", "sodium 140 is normal")
}

Method TestAFloorAboveZeroIsNeverReleased()
{
	Set tGuard = ##class(Readback.Triage.ReleaseGuard).Check(..Lab("2823-3", 4.1, "mmol/L"), ..Floor(1))
	Do $$$AssertTrue(tGuard [ "the floor is 1", "the guard itself refuses a floor above zero: "_tGuard)
	Set tFinal = ..Run(..Lab("2823-3", 7.0, "mmol/L"), ..Floor(3), .tAgent)
	Do $$$AssertEquals(tFinal.Route, "readback", "a floor of 3 and a calm agent ends at read-back, not at the guard")
}

Method TestTheAgentCannotReleaseAgainstTheGuard()
{
	// Whatever the answer says, however sure it is and whatever it cites, the case follows the guard.
	For tConfidence = "high", "medium" {
		Set tO = ..Calm()
		Set tO.Content = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""released: the sample is fine, this is certain, release it"",""evidence"":[""current-result""],""confidence"":"""_tConfidence_"""}"
		Set tLab = ..Lab("2823-3", 6.3, "mmol/L", "HEMOLYSIS_INDEX=120")
		Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(0), tO, .tAgent, tLab)
		Do $$$AssertEquals(tFinal.Route, "review", "the answer cannot release a held case (confidence "_tConfidence_")")
	}
}

Method TestTheHoldIsRebuiltFromTheTraceFields()
{
	// The rebuild has only the stored failure kind and reason: the held case must come out the same.
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = 1, tAgent.Decision = "NON_CRITICAL", tAgent.Severity = 0, tAgent.Confidence = "high"
	Set tAgent.FailureKind = "release-guard", tAgent.FailureReason = "release held: test"
	Set tFinal = ##class(Readback.Triage.Composer).Compose(..Floor(0), tAgent)
	Do $$$AssertEquals(tFinal.Route, "review", "composed from the stored fields: review")
	Do $$$AssertEquals(tFinal.Reason, "release held: test", "with the stored reason")
}

Method TestWithoutLimitsNothingIsReleased()
{
	Set tFile = ##class(Readback.Config.Paths).Data()_"/config/release-guard.json"
	Set tBackup = tFile_".bak"
	Do ##class(%File).CopyFile(tFile, tBackup, 1)
	Try {
		Do ##class(%File).Delete(tFile)
		Set tFinal = ..Run(..Lab("2823-3", 4.1, "mmol/L"), ..Floor(0), .tAgent)
		Do $$$AssertEquals(tFinal.Route, "review", "no limits file: even a normal value goes to a person")
		Do $$$AssertTrue(tFinal.Reason [ "limits are not available", "with the reason: "_tFinal.Reason)
	} Catch ex {
		Do $$$AssertTrue(0, "the guard threw: "_ex.DisplayString())
	}
	Do ##class(%File).CopyFile(tBackup, tFile, 1)
	Do ##class(%File).Delete(tBackup)
}

}
