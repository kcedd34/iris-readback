/// The tool set is what the platform generates from its definition at compile time: the four tools, each marked
/// read-only, with the audit policy attached once. A tool set compiled before its policy exists is generated without
/// its policy getter and the agent job dies at start (found on the first end-to-end run), so this is checked here.
Class Readback.Test.ToolSetTest Extends %UnitTest.TestCase
{

Method TestTheFourToolsAreDiscovered()
{
	Set tSet = ##class(Readback.Tools.ToolSet).%New()
	Set tTools = tSet.%Discover().tools
	Set tNames = ""
	For i = 0:1:tTools.%Size()-1 { Set tNames = tNames_$Select(tNames="":"", 1:",")_tTools.%Get(i).name }
	Do $$$AssertEquals(tNames, "get_patient_history,get_delta_assessment,search_policy,get_sample_quality", "the four tools, in the order of the definition")
}

Method TestNoToolOffersAnIdentifierArgument()
{
	Set tTools = ##class(Readback.Tools.ToolSet).%New().%Discover().tools
	For i = 0:1:tTools.%Size()-1 {
		Set tTool = tTools.%Get(i)
		Set tProps = tTool.parameters.properties
		Set tIter = tProps.%GetIterator()
		While tIter.%GetNext(.tKey) {
			Do $$$AssertTrue(($ZConvert(tKey, "L") '[ "patient") && ($ZConvert(tKey, "L") '[ "case"), tTool.name_" has no identifier parameter ("_tKey_")")
		}
	}
}

Method TestEveryToolIsMarkedReadOnly()
{
	Set tTools = ##class(Readback.Tools.ToolSet).%New().%Discover().tools
	For i = 0:1:tTools.%Size()-1 {
		Set tMeta = tTools.%Get(i).metadata
		Do $$$AssertEquals(tMeta.ReadOnly, "1", tTools.%Get(i).name_" carries the read-only requirement")
	}
}

Method TestThePoliciesAreAttached()
{
	Set tSet = ##class(Readback.Tools.ToolSet).%New()
	Set tAudit = tSet.%GetAuditPolicy()
	Do $$$AssertTrue($IsObject(tAudit), "the audit policy getter was generated and returns a policy")
	Do $$$AssertEquals($ClassName(tAudit), "Readback.Governance.AuditPolicy", "it is the product's audit policy")
}

}
