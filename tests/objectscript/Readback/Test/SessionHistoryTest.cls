/// Reading the exported history of an agent session: the ordered tool calls, and the failures the platform hides from the caller.
Class Readback.Test.SessionHistoryTest Extends %UnitTest.TestCase
{

ClassMethod Export(pTools As %String, pMessages As %String) As %String
{
	Quit "{""version"":1,""messages"":[{""role"":""user"",""content"":""Case""}"_pTools_pMessages_"]}"
}

ClassMethod Call(pId As %String, pName As %String) As %String
{
	Quit ",{""role"":""assistant"",""content"":null,""tool_calls"":[{""id"":"""_pId_""",""name"":"""_pName_""",""arguments"":""{}""}]}"
}

ClassMethod Result(pId As %String, pContent As %String) As %String
{
	Quit ",{""role"":""tool"",""tool_call_id"":"""_pId_""",""content"":"_pContent_"}"
}

Method TestOkCallsKeepTheirOrder()
{
	Set tExport = ..Export(..Call("a", "get_patient_history")_..Call("b", "get_sample_quality"), ..Result("a", """{\""found\"":0}""")_..Result("b", """{\""indices\"":[]}"""))
	Set tCalls = ##class(Readback.Agent.History).Calls(tExport)
	Do $$$AssertEquals(tCalls.%Size(), 2, "two calls")
	Do $$$AssertEquals(tCalls.%Get(0).tool, "get_patient_history", "the first call comes first")
	Do $$$AssertEquals(tCalls.%Get(1).tool, "get_sample_quality", "the second call comes second")
	Do $$$AssertEquals(tCalls.%Get(0).status, "ok", "ok")
	Do $$$AssertEquals(tCalls.%Get(0).result, "{""found"":0}", "a string value is unwrapped once")
	Do $$$AssertEquals(##class(Readback.Agent.History).FirstFailure(tCalls), "", "no failure")
}

Method TestADenialIsRefused()
{
	Set tExport = ..Export(..Call("a", "get_patient_history"), ..Result("a", """{\""error\"":\""Access denied: Provider policy denied: patient out of scope\""}"""))
	Set tCall = ##class(Readback.Agent.History).Calls(tExport).%Get(0)
	Do $$$AssertEquals(tCall.status, "refused", "a denial is refused")
	Do $$$AssertTrue(tCall.reason["denied", "the reason is kept")
}

Method TestAnUnknownToolIsUnknown()
{
	Set tExport = ..Export(..Call("a", "no_such_tool"), ..Result("a", """{\""error\"":\""Tool 'no_such_tool' not found\""}"""))
	Do $$$AssertEquals(##class(Readback.Agent.History).Calls(tExport).%Get(0).status, "unknown-tool", "an unknown tool")
}

Method TestAFailureIsFailed()
{
	Set tExport = ..Export(..Call("a", "search_policy"), ..Result("a", """{\""error\"":\""policy search is unavailable\""}"""))
	Set tCall = ##class(Readback.Agent.History).Calls(tExport).%Get(0)
	Do $$$AssertEquals(tCall.status, "failed", "a plain error is a failure")
	Do $$$AssertEquals(##class(Readback.Agent.History).FirstFailure(##class(Readback.Agent.History).Calls(tExport)).tool, "search_policy", "it is the case's failure")
}

Method TestACallWithNoResultFails()
{
	Set tCalls = ##class(Readback.Agent.History).Calls(..Export(..Call("a", "get_delta_assessment"), ""))
	Do $$$AssertEquals(tCalls.%Get(0).status, "failed", "no result is a failure")
}

Method TestParallelCallsInOneMessage()
{
	Set tBoth = ",{""role"":""assistant"",""content"":null,""tool_calls"":[{""id"":""a"",""name"":""get_patient_history"",""arguments"":""{}""},{""id"":""b"",""name"":""get_sample_quality"",""arguments"":""{}""}]}"
	Set tCalls = ##class(Readback.Agent.History).Calls(..Export(tBoth, ..Result("b", """{}""")_..Result("a", """{}""")))
	Do $$$AssertEquals(tCalls.%Size(), 2, "two calls from one message")
	Do $$$AssertEquals(tCalls.%Get(0).tool, "get_patient_history", "in the order made, not the order answered")
}

Method TestAnUnreadableHistoryIsAFailure()
{
	Set tCalls = ##class(Readback.Agent.History).Calls("not json")
	Do $$$AssertEquals(tCalls.%Get(0).status, "failed", "an unreadable history is a failure, not silence")
}

Method TestNoToolCallsMeansNoCalls()
{
	Do $$$AssertEquals(##class(Readback.Agent.History).Calls(..Export("", "")).%Size(), 0, "none")
}

}
