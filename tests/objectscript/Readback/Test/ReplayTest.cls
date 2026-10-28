/// Replay mode: recorded answers keyed by case id, prompt version and set; same types as the live item.
Class Readback.Test.ReplayTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Do ##class(Readback.Replay.Recording).Activate("default")
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Replay.Recording WHERE ReplaySet LIKE 'unit-%')
}

ClassMethod Add(pSet As %String, pId As %String, pAnswer As %String, pVersion As %String = "triage-v1")
{
	Set tRec = ##class(Readback.Replay.Recording).%New()
	Set tRec.ReplaySet = pSet, tRec.MessageControlId = pId, tRec.PromptVersion = pVersion
	Set tRec.AnswerText = pAnswer, tRec.Model = "fixture", tRec.InputTokens = 120, tRec.OutputTokens = 40
	Do tRec.%Save()
}

ClassMethod Request(pCaseId As %String) As EnsLib.AI.Messages.TextRequest
{
	Set tReq = ##class(EnsLib.AI.Messages.TextRequest).%New()
	Set tReq.TextMessage = ##class(EnsLib.AI.Content.Text).%New()
	Set tReq.TextMessage.String = "Lab result to triage."_$Char(10)_"Case id: "_pCaseId_$Char(10)_"Patient: SYN1, age 40 years"_$Char(10)
	Quit tReq
}

Method TestLookupByCaseVersionAndSet()
{
	Do ..Add("unit-a", "RP-1", "{""a"":1}")
	Do ##class(Readback.Replay.Recording).Activate("unit-a")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-1", "triage-v1").AnswerText, "{""a"":1}", "found in the active set")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-1", "triage-v2"), "", "another prompt version has no recording")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-2", "triage-v1"), "", "an unknown case has no recording")
	Do ##class(Readback.Replay.Recording).Activate("unit-b")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-1", "triage-v1"), "", "another set does not see it")
}

Method TestTheActiveSetCanBeSwitched()
{
	Do ..Add("unit-c", "RP-3", "{""set"":""c""}")
	Do ..Add("unit-d", "RP-3", "{""set"":""d""}")
	Do ##class(Readback.Replay.Recording).Activate("unit-c")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-3", "triage-v1").AnswerText, "{""set"":""c""}", "set c")
	Do ##class(Readback.Replay.Recording).Activate("unit-d")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-3", "triage-v1").AnswerText, "{""set"":""d""}", "set d")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).ActiveSet(), "unit-d", "the active set name is reported")
}

Method TestTwoLookupsGiveTheSameText()
{
	Do ..Add("unit-e", "RP-4", "{""same"":true}")
	Do ##class(Readback.Replay.Recording).Activate("unit-e")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).Lookup("RP-4", "triage-v1").AnswerText, ##class(Readback.Replay.Recording).Lookup("RP-4", "triage-v1").AnswerText, "deterministic")
}

Method TestOperationAnswersWithTheLiveResponseType()
{
	Do ..Add("unit-f", "RP-5", "{""decision"":""NON_CRITICAL""}", ##class(Readback.Triage.Prompt).#Version)
	Do ##class(Readback.Replay.Recording).Activate("unit-f")
	Set tOp = ##class(Readback.Agent.ReplayOperation).%New("Readback.Agent.Replay")
	Set tSC = tOp.OnTextRequest(..Request("RP-5"), .tResp)
	Do $$$AssertStatusOK(tSC, "a recorded case is answered")
	Do $$$AssertEquals(tResp.%ClassName(1), "EnsLib.AI.Messages.LLMResponse", "with the same response class as the live item")
	Do $$$AssertEquals(tResp.Content, "{""decision"":""NON_CRITICAL""}", "content is the recorded text")
	Do $$$AssertEquals(tResp.Usage.%Get("prompt_tokens"), 120, "usage carries the recorded input tokens")
	Do $$$AssertEquals(tResp.Usage.%Get("completion_tokens"), 40, "and the recorded output tokens")
}

Method TestUnknownCaseIsAnErrorWithTheFixedReason()
{
	Do ##class(Readback.Replay.Recording).Activate("unit-g")
	Set tOp = ##class(Readback.Agent.ReplayOperation).%New("Readback.Agent.Replay")
	Set tSC = tOp.OnTextRequest(..Request("RP-none"), .tResp)
	Do $$$AssertStatusNotOK(tSC, "no recording is an error")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["no recorded answer", "with the fixed reason")
}

Method TestCaseIdIsReadFromTheContextText()
{
	Do $$$AssertEquals(##class(Readback.Agent.ReplayOperation).CaseId("x"_$Char(10)_"Case id: ABC-123"_$Char(10)_"y"), "ABC-123", "plain")
	Do $$$AssertEquals(##class(Readback.Agent.ReplayOperation).CaseId("no case here"), "", "absent")
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = "RP-CTX", tLab.PatientId = "SYN7", tLab.AnalyteCode = "2823-3", tLab.ValueText = "6.9", tLab.CollectedAt = "2026-03-01 08:00:00"
	Do $$$AssertEquals(##class(Readback.Agent.ReplayOperation).CaseId(##class(Readback.Triage.Context).Build(tLab)), "RP-CTX", "the id written by the context builder is read back")
}

Method TestLoadFileReplacesTheSetsInTheFile()
{
	Set tFile = "/tmp/readback-replay-test.jsonl"
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tFile)
	Do tStream.WriteLine("{""messageControlId"":""RP-L1"",""promptVersion"":""triage-v1"",""replaySet"":""unit-l"",""answer"":""{}"",""model"":""fixture"",""inputTokens"":1,""outputTokens"":2,""source"":""fixture""}")
	Do tStream.WriteLine("{""messageControlId"":""RP-L2"",""promptVersion"":""triage-v1"",""replaySet"":""unit-l"",""answer"":""{}"",""model"":""fixture"",""inputTokens"":1,""outputTokens"":2,""source"":""recorded""}")
	Do tStream.%Save()
	Set tSC = ##class(Readback.Replay.Recording).LoadFile(tFile, .tN)
	Do $$$AssertStatusOK(tSC, "a valid file loads")
	Do $$$AssertEquals(tN, 2, "two rows loaded")
	Do ##class(Readback.Replay.Recording).LoadFile(tFile, .tN2)
	&sql(SELECT COUNT(*) INTO :tCount FROM Readback_Replay.Recording WHERE ReplaySet = 'unit-l')
	Do $$$AssertEquals(tCount, 2, "loading again replaces the set instead of adding to it")
	Do ##class(%File).Delete(tFile)
}

Method TestMalformedFileIsRejected()
{
	Set tFile = "/tmp/readback-replay-bad.jsonl"
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tFile)
	Do tStream.WriteLine("not json")
	Do tStream.%Save()
	Do $$$AssertStatusNotOK(##class(Readback.Replay.Recording).LoadFile(tFile, .tN), "a line that is not JSON is rejected")
	Do ##class(%File).Delete(tFile)
}

}
