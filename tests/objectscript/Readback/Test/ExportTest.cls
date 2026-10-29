/// The export of a run: exactly the fields the report and the recordings need, redacted, never the input text.
Class Readback.Test.ExportTest Extends %UnitTest.TestCase
{

Parameter FILE = "/tmp/readback-export-test.jsonl";

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Kill ^||ReadbackTestKey
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId %STARTSWITH 'EXPT-')
	Do ##class(%File).Delete(..#FILE)
}

ClassMethod Row(pId As %String, pMode As %String, pRaw As %String, pLatency As %Integer, pRecorded As %Integer)
{
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = pId, tRow.SessionId = 1, tRow.Mode = pMode, tRow.Model = "m-test", tRow.PromptVersion = "triage-v2"
	Set tRow.InputText = "THE INPUT TEXT MUST NOT BE EXPORTED", tRow.RawOutput = pRaw, tRow.AgentCalled = 1, tRow.SchemaValid = 1
	Set tRow.FloorSeverity = 3, tRow.AgentDecision = "CRITICAL", tRow.AgentSeverity = 3, tRow.FinalSeverity = 3, tRow.Route = "readback"
	Set tRow.InputTokens = 700, tRow.OutputTokens = 100, tRow.CostUsd = 0.0033, tRow.CostKnown = 1
	Set tRow.LatencyMs = pLatency, tRow.RecordedLatencyMs = pRecorded
	Do tRow.%Save()
}

ClassMethod Lines() As %List
{
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(..#FILE)
	Set tList = ""
	While 'tStream.AtEnd { Set tList = tList_$ListBuild(tStream.ReadLine()) }
	Quit tList
}

Method TestTheLineHasTheListedFields()
{
	Do ..Row("EXPT-1", "live", "{""decision"":""CRITICAL""}", 2400, "")
	Do $$$AssertStatusOK(##class(Readback.Eval.Export).Rows(..#FILE, "EXPT-1", .tCount), "the export runs")
	Do $$$AssertEquals(tCount, 1, "one row")
	Set tObj = {}.%FromJSON($ListGet(..Lines(), 1))
	Set tNames = "", tIter = tObj.%GetIterator()
	While tIter.%GetNext(.tKey) { Set tNames = tNames_$ListBuild(tKey) }
	Set tExpected = $ListBuild("messageControlId", "mode", "model", "promptVersion", "agentCalled", "schemaValid", "failureKind", "failureReason", "floorSeverity", "agentDecision", "agentSeverity", "finalSeverity", "route", "divergence", "inputTokens", "outputTokens", "costUsd", "costKnown", "latencyMs", "rawOutput")
	Do $$$AssertEquals($ListToString($ListFromString($ListToString(tNames))), $ListToString(tExpected), "the fields, in order")
	Do $$$AssertEquals(tObj.latencyMs, 2400, "live latency is the measured one")
	Do $$$AssertEquals(tObj.model, "m-test", "the model is exported")
	Do $$$AssertTrue(tObj.%GetTypeOf("agentCalled") = "boolean", "flags are booleans")
}

Method TestNoLineHoldsTheInputText()
{
	Do ..Row("EXPT-2", "live", "{}", 100, "")
	Do ##class(Readback.Eval.Export).Rows(..#FILE, "EXPT-2", .tCount)
	Set tText = ""
	Set tPtr = 0, tLines = ..Lines()
	While $ListNext(tLines, tPtr, tLine) { Set tText = tText_tLine }
	Do $$$AssertNotTrue(tText [ "INPUT TEXT", "the input text is not in the file")
	Do $$$AssertNotTrue(tText [ "inputText", "and there is no field for it")
}

Method TestReplayRecordedLatency()
{
	Do ..Row("EXPT-3", "replay", "{}", 4, 2400)
	Do ##class(Readback.Eval.Export).Rows(..#FILE, "EXPT-3", .tCount)
	Do $$$AssertEquals(tCount, 1, "only the prefix asked for")
	Do $$$AssertEquals({}.%FromJSON($ListGet(..Lines(), 1)).latencyMs, 2400, "the latency is the recorded one, not the measured 4")
}

Method TestCredentialInRawRedacted()
{
	Set ^||ReadbackTestKey = "key-for-the-export-test-0123456789"
	Do ..Row("EXPT-4", "live", "echo of the credential: key-for-the-export-test-0123456789 and Bearer abcdef0123456789", 100, "")
	Do ##class(Readback.Eval.Export).Rows(..#FILE, "EXPT-4", .tCount)
	Set tLine = $ListGet(..Lines(), 1)
	Do $$$AssertNotTrue(tLine [ "key-for-the-export-test", "the configured key is not in the file")
	Do $$$AssertNotTrue(tLine [ "abcdef0123456789", "a bearer value is not in the file")
	Do $$$AssertTrue(tLine [ "[key redacted]", "the redaction mark is")
	Kill ^||ReadbackTestKey
}

}
