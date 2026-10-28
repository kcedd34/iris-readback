/// The retrieval engine against the real embedding model of the image: by meaning, deterministic, learning only
/// from cases a person confirmed, and honest about failing.
Class Readback.Test.RetrievalTest Extends %UnitTest.TestCase
{

Property Engine As Readback.Retrieval.Engine;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Engine = ##class(Readback.Retrieval.Engine).%New()
	Do ..Engine.Build()
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	If $IsObject(..Engine) && ..Engine.Available { Do ..Engine.Search(..Request("potassium")) }
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'RTV-%')
	&sql(DELETE FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'RTV-%')
}

ClassMethod Request(pQuery As %String, pPassages As %Integer = 3, pCases As %Integer = 3) As Readback.Msg.RetrievalRequest
{
	Set tReq = ##class(Readback.Msg.RetrievalRequest).%New()
	Set tReq.Query = pQuery, tReq.MaxPassages = pPassages, tReq.MaxCases = pCases
	Quit tReq
}

/// A stored result and its trace record. pConfirm: "", "confirmed" or "reviewed".
ClassMethod Case(pN As %Integer, pValue As %String, pConfirm As %String = "", pExtra As %String = "") As %Integer
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = "RTV-"_pN, tLab.PatientId = "SYN8"_$Justify(pN, 6, 0), tLab.AnalyteCode = "2823-3"
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = "mmol/L", tLab.AgeYears = 60, tLab.Source = "file"
	Set tLab.CollectedAt = "2026-04-01 08:00:00"
	Do:pExtra'="" tLab.SampleIndices.Insert(pExtra)
	Do tLab.%Save()
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = "RTV-"_pN, tTrace.SessionId = pN, tTrace.FinalSeverity = 3, tTrace.Route = "readback"
	Set tTrace.ConversionOutcome = "not-needed", tTrace.ConvertedValue = pValue, tTrace.ConvertedUnit = "mmol/L"
	Set:pConfirm="confirmed" tTrace.ConfirmedBy = "communicator1"
	Set:pConfirm="reviewed" tTrace.ReviewedBy = "reviewer1"
	Do tTrace.%Save()
	Quit tTrace.%Id()
}

/// The trace ids of the cases of an answer, as ",id,id,": the pool may also hold real confirmed cases of earlier
/// runs, so tests look for their own cases by id instead of counting.
ClassMethod Ids(pResp As Readback.Msg.RetrievalResponse) As %String
{
	Set tIds = ","
	For i = 1:1:pResp.Cases.Count() { Set tIds = tIds_pResp.Cases.GetAt(i).TraceId_"," }
	Quit tIds
}

Method Ready() As %Boolean
{
	Quit $$$AssertTrue(..Engine.Available, "the engine is available (model cache of the image): "_..Engine.Reason)
}

Method TestHemolyzedPotassiumRetrievesTheRecollectProtocol()
{
	If '..Ready() { Quit }
	Set tResp = ..Engine.Search(..Request("Potassium 6.9 mmol/L, adult, sample indices hemolysis 250, no earlier results."))
	Set tIds = ""
	For i = 1:1:tResp.Passages.Count() { Set tIds = tIds_","_tResp.Passages.GetAt(i).Id }
	Do $$$AssertTrue(tIds[",recollect-hemolysis", "recollect-hemolysis is among the top 3: "_tIds)
	Do $$$AssertTrue(tResp.Passages.Count() <= 3, "at most 3 passages")
}

Method TestHemoglobinDropRetrievesTheAcuteDropRule()
{
	If '..Ready() { Quit }
	Set tResp = ..Engine.Search(..Request("Hemoglobin 8.1 g/dL, adult, no sample quality problem, earlier results 12.0 g/dL."))
	Set tIds = ""
	For i = 1:1:tResp.Passages.Count() { Set tIds = tIds_","_tResp.Passages.GetAt(i).Id }
	Do $$$AssertTrue(tIds[",ctx-acute-drop", "ctx-acute-drop is among the top 3: "_tIds)
}

Method TestMinimumScoreAndMaximums()
{
	If '..Ready() { Quit }
	Set tResp = ..Engine.Search(..Request("Potassium 6.9 mmol/L, adult, no sample quality problem, no earlier results.", 2, 2))
	Do $$$AssertTrue(tResp.Passages.Count() <= 2, "the passage maximum is respected")
	For i = 1:1:tResp.Passages.Count() { Do $$$AssertTrue(tResp.Passages.GetAt(i).Score >= 0.3, "every score is at least 0.30") }
	Do $$$AssertEquals(tResp.Available, 1, "available")
	Do $$$AssertTrue(tResp.IndexVersion'="", "the index version is returned")
}

Method TestSameInputSameAnswer()
{
	If '..Ready() { Quit }
	Set tQuery = "Potassium 6.9 mmol/L, adult, sample indices hemolysis 250, no earlier results."
	Set tA = ##class(Readback.Retrieval.Engine).Signature(..Engine.Search(..Request(tQuery)))
	Set tB = ##class(Readback.Retrieval.Engine).Signature(..Engine.Search(..Request(tQuery)))
	Do $$$AssertTrue(tA'="", "there is something to compare")
	Do $$$AssertEquals(tA, tB, "same passages, same scores, same order")
}

Method TestNothingRelevantIsAnAvailableEmptyAnswer()
{
	If '..Ready() { Quit }
	Set tResp = ..Engine.Search(..Request("banana smoothie recipe with oats and honey"))
	Do $$$AssertEquals(tResp.Available, 1, "finding nothing is not a failure")
	Do $$$AssertEquals(tResp.Passages.Count(), 0, "no passage")
	Do $$$AssertEquals(tResp.Cases.Count(), 0, "no case")
	Set tText = ##class(Readback.Triage.Context).RetrievalSection(tResp)
	Do $$$AssertTrue(tText["No policy passage matched.", "the agent text says nothing matched")
	Do $$$AssertTrue(tText["No similar confirmed case.", "and no similar confirmed case")
}

Method TestOnlyConfirmedCasesAreRetrievable()
{
	If '..Ready() { Quit }
	Do ..Clean()
	Set tQuery = "Potassium 7.1 mmol/L, adult, no sample quality problem, no earlier results."
	Set tUnconfirmed = ..Case(1, "7.1", "")
	Set tResp = ..Engine.Search(..Request(tQuery, 3, 10))
	Do $$$AssertTrue(..Ids(tResp)'[(","_tUnconfirmed_","), "an unconfirmed case is never retrievable")
	Set tTraceId = ..Case(2, "7.1", "confirmed")
	Set tResp = ..Engine.Search(..Request(tQuery, 3, 10))
	Do $$$AssertTrue(..Ids(tResp)[(","_tTraceId_","), "a case with a matched read-back is retrievable on the very next search")
	Do $$$AssertTrue(..Ids(tResp)'[(","_tUnconfirmed_","), "and the unconfirmed one still is not")
	Set tItem = ""
	For i = 1:1:tResp.Cases.Count() { If tResp.Cases.GetAt(i).TraceId = tTraceId { Set tItem = tResp.Cases.GetAt(i) } }
	If $$$AssertTrue($IsObject(tItem), "found the item") {
		Do $$$AssertTrue(tItem.Id [ "similar-case-", "labelled for the agent: "_tItem.Id)
		Do $$$AssertEquals(tItem.Route, "readback", "with its route")
		Do $$$AssertEquals(tItem.Decision, "critical", "and its decision")
		Do $$$AssertTrue(tItem.Text'["RTV-", "no message id in the text")
		Do $$$AssertTrue(tItem.Text'["SYN8", "no patient id in the text")
	}
	Set tReviewed = ..Case(3, "7.2", "reviewed")
	Set tResp = ..Engine.Search(..Request(tQuery, 3, 10))
	Do $$$AssertTrue(..Ids(tResp)[(","_tReviewed_","), "a completed review makes its case retrievable too")
	Set tResp = ..Engine.Search(..Request(tQuery, 3, 3))
	Do $$$AssertTrue(tResp.Cases.Count() <= 3, "at most 3 cases")
}

Method TestDeletedTraceLeavesThePool()
{
	If '..Ready() { Quit }
	Do ..Clean()
	Set tQuery = "Potassium 7.3 mmol/L, adult, no sample quality problem, no earlier results."
	Set tTraceId = ..Case(10, "7.3", "confirmed")
	Do $$$AssertTrue(..Ids(..Engine.Search(..Request(tQuery, 3, 10)))[(","_tTraceId_","), "the case is in the pool")
	Do ##class(Readback.Trace.Decision).%DeleteId(tTraceId)
	Do $$$AssertTrue(..Ids(..Engine.Search(..Request(tQuery, 3, 10)))'[(","_tTraceId_","), "a deleted trace record leaves the pool at the next sync")
}

Method TestEqualCasesComeInAStableOrder()
{
	If '..Ready() { Quit }
	Do ..Clean()
	Set tQuery = "Potassium 7.4 mmol/L, adult, no sample quality problem, no earlier results."
	Set tA = ..Case(20, "7.4", "confirmed"), tB = ..Case(21, "7.4", "confirmed")
	Set tFirst = ..Engine.Search(..Request(tQuery, 3, 10)), tSecond = ..Engine.Search(..Request(tQuery, 3, 10))
	Set tIds = ..Ids(tFirst)
	Do $$$AssertTrue(tIds[(","_tA_",")&&(tIds[(","_tB_",")), "both are found")
	Do $$$AssertTrue($Find(tIds, ","_tA_",") < $Find(tIds, ","_tB_","), "equal scores: the lower trace id first: "_tIds)
	Do $$$AssertEquals(tIds, ..Ids(tSecond), "and the same order again")
}

Method TestNoIdentifierInEitherVectorTable()
{
	If '..Ready() { Quit }
	Do ..Case(30, "7.5", "confirmed", "hemolysis 250")
	Do ..Engine.Search(..Request("potassium"))
	For tTable = "Readback_Retrieval.PolicyVec", "Readback_Retrieval.CaseVec" {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT text FROM "_tTable)
		Set tBad = 0, tRows = 0
		While tRS.%Next() {
			Set tRows = tRows + 1
			If tRS.%Get("text") ?.E1"SYN"1.N.E { Set tBad = tBad + 1 }
			If tRS.%Get("text") [ "RTV-" { Set tBad = tBad + 1 }
			If tRS.%Get("text") ?.E1"RB"1.UN1"-"1.N.E { Set tBad = tBad + 1 }
		}
		Do $$$AssertTrue(tRows > 0, tTable_" has rows")
		Do $$$AssertEquals(tBad, 0, tTable_" holds no patient or message identifier")
	}
}

Method TestMissingModelIsUnavailableWithAReasonAndNoException()
{
	Set tEngine = ##class(Readback.Retrieval.Engine).%New()
	Set tSC = tEngine.Build("/tmp/readback-no-such-cache")
	Do $$$AssertStatusOK(tSC, "Build does not raise")
	Do $$$AssertEquals(tEngine.Available, 0, "no model means not available")
	Do $$$AssertTrue(tEngine.Reason["not in the cache directory", "the reason says so: "_tEngine.Reason)
	Do $$$AssertTrue(tEngine.Reason["does not download", "and that nothing is downloaded at run time")
	Set tResp = tEngine.Search(..Request("potassium"))
	Do $$$AssertEquals(tResp.Available, 0, "a search on an unavailable engine says unavailable, not 'nothing found'")
	Do $$$AssertEquals(tResp.Passages.Count(), 0, "with no items")
	Do $$$AssertTrue(tResp.Reason'="", "and a reason")
	Do $$$AssertTrue(##class(Readback.Triage.Context).RetrievalSection(tResp)["not available", "the agent text states that retrieval is not available")
}

}
