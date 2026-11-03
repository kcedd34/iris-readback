/// The sentences of the read-back task: the rule with its value and its limit, the change with its window, and each cited
/// identifier resolved to what the tool returned.
Class Readback.Test.TaskTextTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Lab(pId As %String, pPatient As %String, pCode As %String, pValue As %Numeric, pUnit As %String, pCollected As %String) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pId, tLab.PatientId = pPatient, tLab.AnalyteCode = pCode
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.CollectedAt = pCollected, tLab.Source = "file"
	Quit tLab
}

ClassMethod Trace(pLab As Readback.Msg.LabResult) As Readback.Trace.Decision
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(pLab)
	Do ##class(Readback.Triage.Delta).Apply(pLab, pLab, tFloor)
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = pLab.MessageControlId, tTrace.FloorRuleId = tFloor.RuleId
	Quit tTrace
}

Method TestTheValueRuleShowsTheValueAndTheLimit()
{
	Set tLab = ..Lab("TT-VAL-1", "SYN9700001", "2823-3", 6.9, "mmol/L", "2026-03-01 08:00:00")
	Set tLines = ##class(Readback.Trace.TaskText).RuleLines(..Trace(tLab), tLab, "Potassium")
	Do $$$AssertEquals(tLines.%Size(), 1)
	Do $$$AssertEquals(tLines.%Get(0), "6.9 mmol/L "_$Char(8805)_" 6.5 mmol/L, potassium critical high limit, adult range")
}

Method TestALowLimitIsShownAsALowLimit()
{
	Set tLab = ..Lab("TT-VAL-2", "SYN9700002", "2823-3", 2.1, "mmol/L", "2026-03-01 08:00:00")
	Set tLines = ##class(Readback.Trace.TaskText).RuleLines(..Trace(tLab), tLab, "Potassium")
	Do $$$AssertEquals(tLines.%Get(0), "2.1 mmol/L "_$Char(8804)_" 2.5 mmol/L, potassium critical low limit, adult range")
}

Method TestTheChangeRuleShowsTheChangeAndTheWindow()
{
	Set tHist = ..Lab("TT-DEL-H", "SYN9700003", "718-7", 13.2, "g/dL", "2026-02-28 12:00:00")
	Do tHist.%Save()
	Set tLab = ..Lab("TT-DEL-1", "SYN9700003", "718-7", 8.0, "g/dL", "2026-02-28 20:00:00")
	Set tLines = ##class(Readback.Trace.TaskText).RuleLines(..Trace(tLab), tLab, "Hemoglobin")
	Do $$$AssertTrue(tLines.%Size() >= 1, "the change rule gives a sentence")
	Set tLast = tLines.%Get(tLines.%Size() - 1)
	Do $$$AssertEquals(tLast, "hemoglobin fell by 5.2 g/dL within 24 hours, more than the 3 g/dL limit of the change rule")
}

Method TestEvidenceResolvesToWhatTheToolsReturned()
{
	Set tLab = ..Lab("TT-EV-1", "SYN9700004", "2823-3", 6.9, "mmol/L", "2026-03-01 08:00:00")
	Do tLab.%Save()
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = "TT-EV-1", tTrace.Route = "readback", tTrace.SessionId = 1
	Do $$$AssertStatusOK(tTrace.%Save())
	Set tId = tTrace.%Id()
	Do ..Call(tTrace, 1, "get_patient_history", "ok", {"found":1,"earlier":[{"id":"earlier-result-1","value":"5.1","unit":"mmol/L","collectedAt":"2026-02-28 19:11:00"}]}.%ToJSON())
	Do ..Call(tTrace, 2, "get_delta_assessment", "ok", {"id":"delta-assessment","floorVerdict":"no critical change","comparable":true,"change":1.8,"unit":"mmol/L","windowHours":24,"limit":1.5,"direction":"either"}.%ToJSON())
	Do ..Call(tTrace, 3, "search_policy", "ok", {"available":true,"passages":[{"id":"crit-potassium","text":"Potassium at or above 6.5","score":0.5}],"similarCases":[{"id":"similar-case-1","text":"x","decision":"CRITICAL","route":"readback","traceId":1}]}.%ToJSON())
	Do ..Call(tTrace, 4, "get_sample_quality", "ok", {"indices":[{"id":"sample-index-hemolysis","code":"HEMOLYSIS_INDEX","value":78}]}.%ToJSON())
	Set tIds = ["current-result","earlier-result-1","delta-assessment","crit-potassium","similar-case-1","sample-index-hemolysis","made-up-id"]
	Set tOut = ##class(Readback.Trace.TaskText).Resolve(tTrace, tLab, tIds)
	Do $$$AssertEquals(tOut.%Size(), 7)
	Do $$$AssertEquals(tOut.%Get(0).text, "Current result: 6.9 mmol/L, collected 2026-03-01 08:00:00")
	Do $$$AssertEquals(tOut.%Get(1).text, "Earlier result: 5.1 mmol/L, collected 2026-02-28 19:11:00")
	Do $$$AssertEquals(tOut.%Get(2).text, "Change against earlier results: rose by 1.8 mmol/L within 24 hours, limit 1.5 mmol/L (no critical change)")
	Do $$$AssertEquals(tOut.%Get(3).text, "Policy passage: Critical potassium")
	Do $$$AssertEquals(tOut.%Get(4).text, "Similar confirmed case, decided CRITICAL (readback)")
	Do $$$AssertEquals(tOut.%Get(5).text, "Sample quality: hemolysis index 78")
	Do $$$AssertEquals(tOut.%Get(6).text, "")
	Do $$$AssertEquals(tOut.%Get(6).id, "made-up-id")
}

ClassMethod Call(pDecision As Readback.Trace.Decision, pSeq As %Integer, pTool As %String, pStatus As %String, pResult As %String)
{
	Set tCall = ##class(Readback.Trace.ToolCall).%New()
	Set tCall.Decision = pDecision, tCall.Seq = pSeq, tCall.Tool = pTool, tCall.Status = pStatus, tCall.ResultJson = pResult
	Do tCall.%Save()
}

Method OnAfterAllTests() As %Status
{
	&sql(DELETE FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'TT-%')
	&sql(DELETE FROM Readback_Trace.ToolCall WHERE Decision IN (SELECT ID FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'TT-%'))
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'TT-%')
	Quit $$$OK
}

}
