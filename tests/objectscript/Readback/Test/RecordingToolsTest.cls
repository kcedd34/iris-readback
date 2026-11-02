/// A recording keeps the ordered tool calls and the rounds of the investigation, and a run whose investigation failed is recorded
/// with its failure so that replay hands the same failure back.
Class Readback.Test.RecordingToolsTest Extends %UnitTest.TestCase
{

Parameter FILE = "/tmp/readback-recording-tools.jsonl";

Method OnAfterAllTests() As %Status
{
	Do ##class(%File).Delete(..#FILE)
	&sql(DELETE FROM Readback_Replay.Recording WHERE ReplaySet = 'rectools')
	Quit $$$OK
}

Method TestCallsAndRoundsAreLoadedAndKeptInOrder()
{
	Set tLine1 = "{""replaySet"":""rectools"",""messageControlId"":""RT-1"",""promptVersion"":""triage-v3"",""answer"":""{}"",""model"":""m"",""inputTokens"":1500,""outputTokens"":170,""latencyMs"":2000,""source"":""recorded"",""rounds"":2,""toolCalls"":[{""seq"":1,""tool"":""get_patient_history"",""arguments"":""{}"",""result"":""{}"",""status"":""ok"",""reason"":"""",""durationMs"":4},{""seq"":2,""tool"":""get_delta_assessment"",""arguments"":""{}"",""result"":""{}"",""status"":""ok"",""reason"":"""",""durationMs"":2}]}"
	Set tLine2 = "{""replaySet"":""rectools"",""messageControlId"":""RT-2"",""promptVersion"":""triage-v3"",""answer"":"""",""failureKind"":""tool-limit"",""failureReason"":""the investigation reached its limit of rounds"",""model"":""m"",""inputTokens"":900,""outputTokens"":200,""latencyMs"":3000,""source"":""recorded"",""rounds"":3}"
	Do ##class(Readback.Test.LoaderTest).Write(..#FILE, tLine1_$Char(10)_tLine2_$Char(10))
	Set tSC = ##class(Readback.Replay.Recording).LoadFile(..#FILE, .tN)
	Do $$$AssertStatusOK(tSC, "the file loads")
	Do $$$AssertEquals(tN, 2, "both rows")
	Set tOne = ##class(Readback.Replay.Recording).KeyIdxOpen("rectools", "RT-1", "triage-v3")
	Do $$$AssertEquals(tOne.Rounds, 2, "the rounds are kept")
	Set tCalls = [].%FromJSON(tOne.ToolCallsJson)
	Do $$$AssertEquals(tCalls.%Get(0).tool, "get_patient_history", "the first call is first")
	Do $$$AssertEquals(tCalls.%Get(1).tool, "get_delta_assessment", "the second is second")
	Do $$$AssertEquals(tOne.InputTokens, 1500, "the tokens are the case totals")
	Set tTwo = ##class(Readback.Replay.Recording).KeyIdxOpen("rectools", "RT-2", "triage-v3")
	Do $$$AssertEquals(tTwo.FailureKind, "tool-limit", "an investigation that hit its limit is recorded as that failure")
	Do $$$AssertEquals(tTwo.ToolCallsJson, "", "and a case with no calls has none")
}

Method TestAnUnknownFailureKindIsRefused()
{
	Do ##class(Readback.Test.LoaderTest).Write(..#FILE, "{""replaySet"":""rectools"",""messageControlId"":""RT-3"",""promptVersion"":""triage-v3"",""answer"":"""",""failureKind"":""made-up"",""model"":""m"",""source"":""recorded""}"_$Char(10))
	Set tSC = ##class(Readback.Replay.Recording).LoadFile(..#FILE, .tN)
	Do $$$AssertStatusNotOK(tSC, "a failure kind the product does not know is not loaded")
}

}
