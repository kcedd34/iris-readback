/// The scope policy, the second layer behind the binding: every rule that denies a call, and that an error inside it denies too.
Class Readback.Test.ScopePolicyTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(Readback.Tools.Binding).Clear()
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod J(pText As %String) As %DynamicObject
{
	Quit {}.%FromJSON(pText)
}

ClassMethod Bind()
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = "SCP-1", tLab.PatientId = "SCP0000001", tLab.AnalyteCode = "2823-3", tLab.ValueText = "6.9", tLab.ValueNumeric = 6.9, tLab.Unit = "mmol/L"
	Do ##class(Readback.Tools.Binding).Publish(tLab, tLab, ##class(Readback.Triage.FloorResult).%New())
	Do ##class(Readback.Tools.Binding).Bind("SCP-1")
	Do ##class(Readback.Governance.AuditPolicy).Reset()
}

ClassMethod Ask(pName As %String, pArgs As %String = "{}", pReadOnly As %String = 1) As %Status
{
	Set tPolicy = ##class(Readback.Governance.ScopePolicy).%New()
	Quit tPolicy.%CanExecute(pName, ..J("{""id"":""c"",""name"":"""_pName_""",""arguments"":"_pArgs_"}"), ..J("{""ReadOnly"":"""_pReadOnly_"""}"))
}

Method TestAnAllowedCallRuns()
{
	Do ..Bind()
	For tTool = "get_patient_history", "get_delta_assessment", "get_sample_quality" { Do $$$AssertStatusOK(..Ask(tTool), tTool_" is allowed") }
	Do $$$AssertStatusOK(..Ask("search_policy", "{""query"":""potassium above the critical limit"",""topK"":3}"), "a policy search with a plain description is allowed")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestNoCaseMeansNoCall()
{
	Do ##class(Readback.Tools.Binding).Clear()
	Do $$$AssertStatusNotOK(..Ask("get_patient_history"), "with no case bound nothing runs")
}

Method TestAToolOutsideTheSetIsDenied()
{
	Do ..Bind()
	Do $$$AssertStatusNotOK(..Ask("delete_everything"), "a tool that is not in the set is denied")
	Do $$$AssertStatusNotOK(..Ask("get_all_patients"), "so is a tool that would reach other patients")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestAToolThatIsNotReadOnlyIsDenied()
{
	Do ..Bind()
	Do $$$AssertStatusNotOK(..Ask("get_patient_history", "{}", ""), "a tool without the read-only requirement is denied")
	Do $$$AssertStatusNotOK(..Ask("get_patient_history", "{}", 0), "and one marked 0")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestAnIdentifierArgumentIsDenied()
{
	Do ..Bind()
	Do $$$AssertStatusNotOK(..Ask("get_patient_history", "{""patientId"":""SCP0000002""}"), "a forged patient identifier is denied")
	Do $$$AssertStatusNotOK(..Ask("get_patient_history", "{""case_id"":""RB2026-00001""}"), "so is a case identifier")
	Do $$$AssertStatusNotOK(..Ask("search_policy", "{""query"":""history of SYN9000001 potassium""}"), "an identifier hidden in a description is denied")
	Do $$$AssertStatusNotOK(..Ask("search_policy", "{""query"":""case RB2026-00034""}"), "so is a case id in a description")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestTheCallCapIsEnforced()
{
	Do ..Bind()
	Set tMax = ##class(Readback.Config.AgentTools).Current().MaxToolCalls
	For i = 1:1:tMax { Do $$$AssertStatusOK(..Ask("get_sample_quality"), "call "_i_" is within the cap") }
	Do $$$AssertStatusNotOK(..Ask("get_sample_quality"), "call "_(tMax + 1)_" is over the cap")
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Do $$$AssertStatusOK(..Ask("get_sample_quality"), "a new case starts counting again")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestAnErrorInsideThePolicyDenies()
{
	Do ..Bind()
	Set tPolicy = ##class(Readback.Governance.ScopePolicy).%New()
	Set tSC = tPolicy.%CanExecute("x", "not an object", {})
	Do $$$AssertStatusNotOK(tSC, "a call the policy cannot read is denied, not allowed and not raised")
	Do ##class(Readback.Tools.Binding).Clear()
}

}
