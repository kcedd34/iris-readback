/// The short summary of a tool call and the audit policy's own entries.
Class Readback.Test.SummaryAuditTest Extends %UnitTest.TestCase
{

Method TestSummaries()
{
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("get_patient_history", "ok", "{""found"":2,""earlier"":[]}"), "2 earlier results", "history")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("get_patient_history", "ok", "{""found"":0}"), "no earlier results", "no history")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("get_delta_assessment", "ok", "{""floorVerdict"":""critical by change""}"), "critical by change", "delta")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("get_sample_quality", "ok", "{""indices"":[]}"), "no quality indices", "sample")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("search_policy", "ok", "{""available"":true,""passages"":[{},{}]}"), "2 policy passages", "policy")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("search_policy", "refused", ""), "refused by the policy", "refused")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Of("x", "unknown-tool", ""), "no such tool", "unknown")
}

ClassMethod J(pText As %String) As %DynamicObject
{
	Quit {}.%FromJSON(pText)
}

Method TestAuditKeepsEntriesInOrder()
{
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Set tPolicy = ##class(Readback.Governance.AuditPolicy).%New()
	Do tPolicy.%LogExecution(..J("{""id"":""c"",""name"":""get_patient_history"",""arguments"":""{\""limit\"":2}""}"), {}, ..J("{""tool_name"":""get_patient_history"",""result_json"":""{\""found\"":1}""}"), 4, $$$OK)
	Do tPolicy.%LogExecution(..J("{""id"":""c"",""name"":""get_sample_quality"",""arguments"":{""x"":1}}"), {}, ..J("{""result_json"":""{}""}"), 1, $$$OK)
	Do tPolicy.%LogDenial(..J("{""id"":""c"",""name"":""search_policy"",""arguments"":""{}""}"), {}, $$$ERROR($$$GeneralError, "Access denied: patient out of scope"))
	Set tEntries = ##class(Readback.Governance.AuditPolicy).Entries()
	Do $$$AssertEquals(tEntries.%Size(), 3, "one entry per call")
	Do $$$AssertEquals(tEntries.%Get(0).tool, "get_patient_history", "in order")
	Do $$$AssertEquals(tEntries.%Get(0).arguments, "{""limit"":2}", "a string argument is kept")
	Do $$$AssertEquals(tEntries.%Get(1).arguments, "{""x"":1}", "an object argument is kept as JSON text")
	Do $$$AssertEquals(tEntries.%Get(2).status, "refused", "a denial is refused")
	Do $$$AssertEquals(tEntries.%Get(0).durationMs, 4, "with the duration")
	Do ##class(Readback.Governance.AuditPolicy).Reset()
}

Method TestAuditFailureIsCounted()
{
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Set tPolicy = ##class(Readback.Governance.AuditPolicy).%New()
	// A call object with no name or arguments is not what the platform sends; the policy must absorb it.
	Set tSC = tPolicy.%LogExecution("not an object", {}, {}, 0, $$$OK)
	Do $$$AssertStatusOK(tSC, "the policy never raises")
	Do $$$AssertEquals(+$Get(^||Readback.AuditFaults), 1, "and it counts its own failure")
	Do ##class(Readback.Governance.AuditPolicy).Reset()
}

}
