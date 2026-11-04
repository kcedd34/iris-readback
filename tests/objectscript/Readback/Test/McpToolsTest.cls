/// The read-only MCP server: four tools, all read-only, none that confirms anything, answers without a patient identifier.
Class Readback.Test.McpToolsTest Extends %UnitTest.TestCase
{

Method TestTheFourToolsAreDiscoveredAndNoneConfirms()
{
	Set tTools = ##class(Readback.MCP.Tools).%New().%Discover().tools
	Set tNames = ""
	For i = 0:1:tTools.%Size()-1 { Set tNames = tNames_$Select(tNames="":"", 1:",")_tTools.%Get(i).name }
	Do $$$AssertEquals(tNames, "list_pending_criticals,explain_decision,read_evaluation,read_ablation", "exactly the four read tools")
	For i = 0:1:tTools.%Size()-1 {
		Set tName = $ZConvert(tTools.%Get(i).name, "L")
		Do $$$AssertTrue((tName '[ "confirm") && (tName '[ "close") && (tName '[ "complete") && (tName '[ "ack"), tName_" is not a tool that confirms or closes anything")
		Do $$$AssertEquals(tTools.%Get(i).metadata.ReadOnly, "1", tName_" is marked read-only")
	}
}

Method TestNoToolTakesAPatientIdentifier()
{
	Set tTools = ##class(Readback.MCP.Tools).%New().%Discover().tools
	For i = 0:1:tTools.%Size()-1 {
		Set tIter = tTools.%Get(i).parameters.properties.%GetIterator()
		While tIter.%GetNext(.tKey) { Do $$$AssertTrue($ZConvert(tKey, "L") '[ "patient", "no patient parameter on "_tTools.%Get(i).name_" ("_tKey_")") }
	}
}

Method TestTheServiceIsGatedByItsResource()
{
	Do $$$AssertEquals(##class(Readback.MCP.Service).#RESOURCE, "Readback_MCP", "the service needs the Readback_MCP resource")
	Do $$$AssertEquals(##class(Readback.MCP.Service).#SPECIFICATION, "Readback.MCP.Tools", "the service serves only the read-only tool set")
}

Method TestACaseIdThatIsNotACaseIdIsRefused()
{
	Set tFailed = 0
	Try { Do ##class(Readback.MCP.Impl).ExplainDecision("SYN0000001 or 1=1") } Catch ex { Set tFailed = 1 }
	Do $$$AssertTrue(tFailed, "a value that is not a case id is refused")
	Set tFailed = 0
	Try { Do ##class(Readback.MCP.Impl).ExplainDecision("RB-NO-SUCH-CASE") } Catch ex { Set tFailed = 1 }
	Do $$$AssertTrue(tFailed, "an unknown case id is refused")
}

Method TestTheEvaluationAndTheAblationAreReadFromTheShippedFiles()
{
	Set tEval = {}.%FromJSON(##class(Readback.MCP.Impl).ReadEvaluation())
	Do $$$AssertTrue(tEval.models.%IsDefined("gpt-5.4") && tEval.models.%IsDefined("gpt-5.4-mini"), "the evaluation has both models")
	Do $$$AssertEquals(tEval.models."gpt-5.4".silencedCriticals, 0, "the evaluation says zero silenced criticals")
	Set tAbl = {}.%FromJSON(##class(Readback.MCP.Impl).ReadAblation())
	Do $$$AssertTrue(tAbl.%IsDefined("agentWithoutVerdict") && 'tAbl.%IsDefined("origin"), "the ablation has the run without the verdict")
}

Method TestAnAnswerNeverCarriesAPatientIdentifierOfTheSyntheticData()
{
	Set tText = ##class(Readback.MCP.Impl).Out({"x":"patient SYN0000123 and SYN123456789"})
	Do $$$AssertTrue(tText '[ "SYN0", "the identifier shape is taken out of an answer")
}

}
