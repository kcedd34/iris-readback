/// Loading the bounds of the agent investigation: whole numbers greater than 0 only, the previous values stay on a rejected load.
Class Readback.Test.AgentToolsConfigTest Extends %UnitTest.TestCase
{

Parameter DIR = "/tmp/readback-agenttoolstest";

Method OnAfterAllTests() As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..#DIR)
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Load(pText As %String) As %Status
{
	Do ##class(Readback.Test.LoaderTest).Write(..#DIR_"/agent-tools.json", pText)
	Quit ##class(Readback.Config.Loader).LoadAgentTools(..#DIR_"/agent-tools.json", .tN)
}

ClassMethod Doc(pIterations As %String = 6, pCalls As %String = 6) As %String
{
	Quit "{""maxIterations"":"_pIterations_",""maxToolCalls"":"_pCalls_",""toolResultMaxChars"":2000,""expectedRounds"":3}"
}

Method TestValidLoad()
{
	Do $$$AssertStatusOK(..Load(..Doc(4, 5)), "a valid file loads")
	Set tRow = ##class(Readback.Config.AgentTools).Current()
	Do $$$AssertEquals(tRow.MaxIterations, 4, "iteration limit loaded")
	Do $$$AssertEquals(tRow.MaxToolCalls, 5, "tool call cap loaded")
	Do $$$AssertEquals(tRow.ExpectedRounds, 3, "expected rounds loaded")
}

Method TestShippedFileLoads()
{
	Set tSC = ##class(Readback.Config.Loader).LoadAgentTools(##class(Readback.Config.Paths).Data()_"/config/agent-tools.json", .tN)
	Do $$$AssertStatusOK(tSC, "the file in data/config loads")
	Do $$$AssertEquals(##class(Readback.Config.AgentTools).Current().MaxIterations, 6, "the shipped limit is 6")
}

Method TestRejectedKeepsPrevious()
{
	Do ..Load(..Doc(3, 3))
	Do $$$AssertStatusNotOK(..Load(..Doc(0, 3)), "zero iterations is rejected")
	Do $$$AssertStatusNotOK(..Load(..Doc(2.5, 3)), "a fraction is rejected")
	Do $$$AssertStatusNotOK(..Load(..Doc("""six""", 3)), "text is rejected")
	Do $$$AssertStatusNotOK(..Load("{""maxIterations"":3}"), "a missing field is rejected")
	Do $$$AssertEquals(##class(Readback.Config.AgentTools).Current().MaxIterations, 3, "the previous value stays")
}

Method TestMissingFileFails()
{
	Set tSC = ##class(Readback.Config.Loader).LoadAgentTools(..#DIR_"/none.json", .tN)
	Do $$$AssertStatusNotOK(tSC, "a missing file is an error")
}

}
