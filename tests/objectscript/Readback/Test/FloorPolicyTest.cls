/// The floor policy: a critical by rule or by change is never lowered. The policy refuses a lowering answer before the
/// composition, and the composition alone holds without it.
Class Readback.Test.FloorPolicyTest Extends %UnitTest.TestCase
{

Method OnAfterAllTests() As %Status
{
	Kill ^Readback("floorPolicyOff")
	Quit $$$OK
}

ClassMethod Floor(pSeverity As %Integer, pDelta As %Boolean = 0) As Readback.Triage.FloorResult
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pSeverity, tFloor.DeltaTriggered = pDelta
	Quit tFloor
}

ClassMethod Answer(pDecision As %String, pSeverity As %Integer) As Readback.Triage.AgentOutput
{
	Set tOut = ##class(Readback.Triage.AgentOutput).%New()
	Set tOut.Valid = 1, tOut.Decision = pDecision, tOut.Severity = pSeverity, tOut.Confidence = "high", tOut.Evidence = "[""current-result""]", tOut.Rationale = "r"
	Quit tOut
}

Method TestALoweringAnswerIsRefused()
{
	Set tText = ##class(Readback.Governance.FloorPolicy).Review(..Floor(3), ..Answer("NON_CRITICAL", 0))
	Do $$$AssertTrue(tText [ "refused", "an answer below the floor is refused: "_tText)
	Do $$$AssertTrue(tText [ "critical by rule", "and says it was held by a rule")
	Do $$$AssertTrue(##class(Readback.Governance.FloorPolicy).Review(..Floor(3, 1), ..Answer("NON_CRITICAL", 0)) [ "critical by change", "or by a change")
	Do $$$AssertTrue(##class(Readback.Governance.FloorPolicy).Review(..Floor(3), ..Answer("NEEDS_REVIEW", 2)) [ "refused", "needing review below the floor is a lowering too")
	Do $$$AssertTrue(##class(Readback.Governance.FloorPolicy).Review(..Floor(3), ..Answer("CRITICAL", 2)) [ "refused", "a CRITICAL decision with a lower severity is refused")
	Do $$$AssertTrue(##class(Readback.Governance.FloorPolicy).Review(..Floor(3), ..Answer("RECOLLECT", 0)) [ "refused", "a recollect request does not lower a critical either")
}

Method TestAnAnswerThatKeepsOrRaisesPassesUnchanged()
{
	Do $$$AssertEquals(##class(Readback.Governance.FloorPolicy).Review(..Floor(3), ..Answer("CRITICAL", 3)), "", "keeping the floor passes")
	Do $$$AssertEquals(##class(Readback.Governance.FloorPolicy).Review(..Floor(0), ..Answer("CRITICAL", 3)), "", "raising above a floor of 0 passes")
	Do $$$AssertEquals(##class(Readback.Governance.FloorPolicy).Review(..Floor(0), ..Answer("NON_CRITICAL", 0)), "", "a floor below critical is not this policy's business")
	Do $$$AssertEquals(##class(Readback.Governance.FloorPolicy).Review(..Floor(2), ..Answer("NON_CRITICAL", 0)), "", "nor is a floor of 2")
}

Method TestAnUnusableAnswerIsNotJudged()
{
	Set tOut = ..Answer("NON_CRITICAL", 0)
	Set tOut.Valid = 0
	Do $$$AssertEquals(##class(Readback.Governance.FloorPolicy).Review(..Floor(3), tOut), "", "an invalid answer is not used by the composition either")
}

Method TestThePolicyRunsBeforeTheCompositionAndIsRecorded()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tO = ##class(Readback.Triage.AgentOutcome).%New()
	Set tO.Content = "{""decision"":""NON_CRITICAL"",""severity"":0,""rationale"":""looks normal"",""evidence"":[""current-result""],""confidence"":""high""}"
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
	Do $$$AssertTrue(tAgent.PolicyRefusal [ "refused", "the refusal is recorded on the agent part: "_tAgent.PolicyRefusal)
	Do $$$AssertEquals(tAgent.FailureKind, "floor-policy-refusal", "with its own failure kind")
	Do $$$AssertEquals(tFinal.FinalSeverity, 3, "and the final severity is the floor's")
	Do $$$AssertEquals(tFinal.Route, "readback", "so the case reaches the read-back")
}

Method TestTheCompositionAloneHoldsWithThePolicyOff()
{
	Set ^Readback("floorPolicyOff") = 1
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	For tDecision = "NON_CRITICAL", "NEEDS_REVIEW", "RECOLLECT", "CRITICAL" {
		For tSeverity = 0:1:3 {
			Set tO = ##class(Readback.Triage.AgentOutcome).%New()
			Set tO.Content = "{""decision"":"""_tDecision_""",""severity"":"_tSeverity_",""rationale"":""r"",""evidence"":[""current-result""],""confidence"":""high""}"
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
			Do $$$AssertEquals(tAgent.PolicyRefusal, "", tDecision_"/"_tSeverity_": the policy is off, so nothing was refused")
			Do $$$AssertEquals(tFinal.FinalSeverity, 3, tDecision_"/"_tSeverity_": the composition alone keeps the critical")
			Do $$$AssertEquals(tFinal.Route, "readback", tDecision_"/"_tSeverity_": and the route is the read-back")
		}
	}
	Kill ^Readback("floorPolicyOff")
}

Method TestEveryCombinationEndsCriticalWithThePolicyOn()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	For tDecision = "NON_CRITICAL", "NEEDS_REVIEW", "RECOLLECT", "CRITICAL" {
		For tSeverity = 0:1:3 {
			Set tO = ##class(Readback.Triage.AgentOutcome).%New()
			Set tO.Content = "{""decision"":"""_tDecision_""",""severity"":"_tSeverity_",""rationale"":""r"",""evidence"":[""current-result""],""confidence"":""high""}"
			Set tFinal = ##class(Readback.Triage.Pipeline).Decide(tLab, ..Floor(3), tO, .tAgent)
			Do $$$AssertEquals(tFinal.FinalSeverity, 3, tDecision_"/"_tSeverity_": still critical")
			Do $$$AssertEquals(tFinal.Route, "readback", tDecision_"/"_tSeverity_": still read-back")
			Set tLowers = (tSeverity < 3) || (tDecision '= "CRITICAL")
			Do $$$AssertEquals(tAgent.PolicyRefusal '= "", tLowers, tDecision_"/"_tSeverity_": refused exactly when it lowers")
		}
	}
}

}
