/// P-1 and P-2: the agent can raise a result and never lower it. Exhaustive over every combination.
/// The expected route is derived here from the composition contract, not by calling the code under test.
Class Readback.Test.ComposerTest Extends %UnitTest.TestCase
{

ClassMethod Floor(pSeverity As %Integer) As Readback.Triage.FloorResult
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pSeverity
	Quit tFloor
}

/// A usable answer. Confidence low carries the low-confidence failure kind, as the parser does.
ClassMethod Agent(pDecision As %String, pSeverity As %Integer, pConfidence As %String) As Readback.Triage.AgentOutput
{
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = 1, tAgent.Decision = pDecision, tAgent.Severity = pSeverity, tAgent.Confidence = pConfidence
	If pConfidence = "low" { Set tAgent.FailureKind = "low-confidence", tAgent.FailureReason = "agent confidence low" }
	Quit tAgent
}

ClassMethod Failure(pKind As %String) As Readback.Triage.AgentOutput
{
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = 0, tAgent.FailureKind = pKind, tAgent.FailureReason = "reason for "_pKind
	Quit tAgent
}

/// The routing table of the contract, written as a separate decision tree.
ClassMethod ExpectedRoute(pFloor As %Integer, pDecision As %String, pSeverity As %Integer, pConfidence As %String) As %String
{
	Set tFinal = $Select(pFloor>pSeverity:pFloor, 1:pSeverity)
	Quit:tFinal=3 "readback"
	Quit:(pDecision="CRITICAL") "review"
	Quit:tFinal>0 "review"
	Quit:pDecision="NEEDS_REVIEW" "review"
	Quit:pConfidence="low" "review"
	Quit:pDecision="RECOLLECT" "recollect"
	Quit:pDecision="NON_CRITICAL" "release"
	Quit "review"
}

ClassMethod ExpectedDivergence(pFloor As %Integer, pDecision As %String, pSeverity As %Integer) As %Boolean
{
	Quit:(pFloor=3)&&((pSeverity<3)||(pDecision'="CRITICAL")) 1
	Quit:(pDecision="NON_CRITICAL")&&(pSeverity>0) 1
	Quit:(pDecision="CRITICAL")&&(pSeverity<3) 1
	Quit 0
}

Method TestEveryCombinationNeverLowersTheFloorAndRoutesAsTheContract()
{
	Set tBad = 0, tCount = 0, tDecisions = $ListBuild("CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL"), tConfs = $ListBuild("low", "medium", "high")
	For tFloor = 0, 3 {
		For tSev = 0:1:3 {
			For d = 1:1:4 {
				For c = 1:1:3 {
					Set tDecision = $List(tDecisions, d), tConf = $List(tConfs, c)
					Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(tFloor), ..Agent(tDecision, tSev, tConf))
					Set tCount = tCount + 1
					Set tWhere = "floor "_tFloor_" agent "_tDecision_"/"_tSev_"/"_tConf
					If tResult.FinalSeverity < tFloor { Set tBad = tBad + 1  Do $$$LogMessage("LOWERED: "_tWhere) }
					If (tFloor = 3) && (tResult.Route '= "readback") { Set tBad = tBad + 1  Do $$$LogMessage("FLOOR 3 NOT READ-BACK: "_tWhere) }
					Set tExpected = ..ExpectedRoute(tFloor, tDecision, tSev, tConf)
					If tResult.Route '= tExpected { Set tBad = tBad + 1  Do $$$LogMessage("ROUTE "_tResult.Route_" EXPECTED "_tExpected_": "_tWhere) }
					Set tDiv = (tResult.Divergence '= "")
					If tDiv '= ..ExpectedDivergence(tFloor, tDecision, tSev) { Set tBad = tBad + 1  Do $$$LogMessage("DIVERGENCE FLAG WRONG: "_tWhere) }
				}
			}
		}
	}
	Do $$$AssertEquals(tCount, 96, "all 96 combinations were exercised")
	Do $$$AssertEquals(tBad, 0, "no combination lowers the floor, mis-routes or mis-flags a divergence")
}

Method TestHostileAgentCannotSilenceARuleCritical()
{
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(3), ..Agent("NON_CRITICAL", 0, "high"))
	Do $$$AssertEquals(tResult.FinalSeverity, 3, "final severity stays critical")
	Do $$$AssertEquals(tResult.Route, "readback", "the case still opens a read-back")
	Do $$$AssertTrue(tResult.Divergence'="", "the divergence between rule and agent is recorded")
	Do $$$AssertEquals(tResult.AgentSeverity, 0, "the agent's own answer is kept")
}

Method TestAgentMayRaise()
{
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(0), ..Agent("CRITICAL", 3, "high"))
	Do $$$AssertEquals(tResult.FinalSeverity, 3, "the agent raises above the floor")
	Do $$$AssertEquals(tResult.Route, "readback", "and the case opens a read-back")
	Do $$$AssertEquals(tResult.Divergence, "", "no divergence when the agent agrees with a raise")
}

Method TestRecollectNeverOverridesACriticalFloor()
{
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(3), ..Agent("RECOLLECT", 1, "medium"))
	Do $$$AssertEquals(tResult.Route, "readback", "a rule-critical result with a recollect advice still goes to read-back")
	Do $$$AssertEquals(tResult.FinalSeverity, 3, "and stays critical")
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(0), ..Agent("RECOLLECT", 1, "medium"))
	Do $$$AssertEquals(tResult.Route, "review", "recollect with severity 1 is not released and goes to review")
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(0), ..Agent("RECOLLECT", 0, "high"))
	Do $$$AssertEquals(tResult.Route, "recollect", "recollect ends the case only when the floor is not critical")
}

Method TestEveryFailureKind()
{
	For tKind = "schema-invalid", "empty-or-refused", "timeout", "provider-error", "no-recorded-answer" {
		Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(0), ..Failure(tKind))
		Do $$$AssertEquals(tResult.Route, "review", tKind_" with floor 0 goes to review")
		Do $$$AssertEquals(tResult.Reason, "reason for "_tKind, tKind_" keeps the literal reason")
		Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(3), ..Failure(tKind))
		Do $$$AssertEquals(tResult.Route, "readback", tKind_" with floor 3 still goes to read-back")
		Do $$$AssertEquals(tResult.FinalSeverity, 3, tKind_" with floor 3 stays critical")
	}
	Set tResult = ##class(Readback.Triage.Composer).Compose(..Floor(0), "")
	Do $$$AssertEquals(tResult.Route, "review", "no answer at all goes to review")
}

}
