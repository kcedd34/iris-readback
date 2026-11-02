/// The four tools the agent calls while it reasons. All are read-only and none takes a patient or case identifier:
/// each reads the case the server bound before the session (Readback.Tools.Binding). A tool returns JSON text, bounded
/// to the configured size; a failure is raised and the product reads it from the session history.
Class Readback.Tools.Impl
{

/// Earlier results of this patient and analyte, newest first: the same window and ceiling the product always used.
ClassMethod PatientHistory(limit As %Integer = 3) As %String
{
	Do ..Require()
	Set tRows = ##class(Readback.Triage.Context).EarlierRows(##class(Readback.Tools.Binding).Get("patientId"), ##class(Readback.Tools.Binding).Get("analyteCode"), ##class(Readback.Tools.Binding).Get("caseId"), ##class(Readback.Tools.Binding).Get("collectedAt"), limit)
	Set tOut = {"found":(tRows.%Size()),"earlier":(tRows)}
	Set:tRows.%Size()=0 tOut.note = "no earlier results in the window"
	Quit ..Bounded(tOut)
}

/// The change of the current value against the patient's earlier results, with the verdict of the change rule.
ClassMethod DeltaAssessment() As %String
{
	Do ..Require()
	Set tAssess = ##class(Readback.Triage.Delta).Assess(##class(Readback.Tools.Binding).Get("patientId"), ##class(Readback.Tools.Binding).Get("analyteCode"), ##class(Readback.Tools.Binding).Get("caseId"), ##class(Readback.Tools.Binding).Get("collectedAt"), ##class(Readback.Tools.Binding).Get("originalNumeric"), ##class(Readback.Tools.Binding).Get("originalUnit"), ##class(Readback.Tools.Binding).Get("effectiveNumeric"), ##class(Readback.Tools.Binding).Get("effectiveUnit"))
	Set tOut = {"id":"delta-assessment","floorVerdict":(tAssess.verdict)}
	Do tOut.%Set("comparable", +tAssess.comparable, "boolean")
	If tAssess.comparable {
		Set tOut.change = tAssess.change, tOut.unit = tAssess.unit, tOut.windowHours = tAssess.windowHours, tOut.limit = tAssess.limit, tOut.direction = tAssess.direction
	}
	Set:tAssess.reason'="" tOut.reason = tAssess.reason
	Quit ..Bounded(tOut)
}

/// Passages of the laboratory policy found by meaning, and similar confirmed cases when there are any. Asks the
/// retrieval operation of the production; when it is unavailable the tool fails and the case goes to a person.
ClassMethod SearchPolicy(query As %String, topK As %Integer = 3) As %String
{
	Do ..Require()
	If '$IsObject($Get(%ReadbackHost)) { Do ..Fail("policy search is not reachable from here") }
	Set tMax = $Select((topK = "") || (topK < 1) || (topK > 5):3, 1:topK)
	Set tRequest = ##class(Readback.Msg.RetrievalRequest).%New()
	Set tRequest.Query = $Extract(query, 1, 1000), tRequest.MaxPassages = tMax, tRequest.MaxCases = tMax
	Set tSC = %ReadbackHost.SendRequestSync("Readback.Retrieval", tRequest, .tResponse, 10)
	If $System.Status.IsError(tSC) { Do ..Fail("policy search failed: "_##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(tSC))) }
	If '$IsObject($Get(tResponse)) || 'tResponse.Available { Do ..Fail("policy search is unavailable: "_$Select($IsObject($Get(tResponse)):tResponse.Reason, 1:"no answer")) }
	Set tPassages = [], tCases = []
	For i = 1:1:tResponse.Passages.Count() {
		Set tItem = tResponse.Passages.GetAt(i)
		Do tPassages.%Push({"id":(tItem.Id),"text":(tItem.Text),"score":(+tItem.Score)})
	}
	For i = 1:1:tResponse.Cases.Count() {
		Set tItem = tResponse.Cases.GetAt(i)
		Do tCases.%Push({"id":("similar-case-"_i),"text":(tItem.Text),"decision":(tItem.Decision),"route":(tItem.Route),"traceId":(tItem.TraceId)})
	}
	Quit ..Bounded({"available":true,"indexVersion":(tResponse.IndexVersion),"passages":(tPassages),"similarCases":(tCases)})
}

/// The sample quality indices of the case, or an explicit statement that there are none.
ClassMethod SampleQuality() As %String
{
	Do ..Require()
	Set tIndices = [], tRaw = ##class(Readback.Tools.Binding).Indices()
	For i = 0:1:tRaw.%Size()-1 {
		Set tEntry = tRaw.%Get(i)
		Set tCode = $Piece(tEntry, "=", 1), tValue = $Piece(tEntry, "=", 2, *)
		Do tIndices.%Push({"id":("sample-index-"_$ZConvert($Piece(tCode, "_INDEX", 1), "L")),"code":(tCode),"value":(tValue)})
	}
	Set tOut = {"indices":(tIndices)}
	Set:tIndices.%Size()=0 tOut.note = "no sample quality indices"
	Quit ..Bounded(tOut)
}

/// A tool never runs without a case bound by the server.
ClassMethod Require() [ Private ]
{
	If '##class(Readback.Tools.Binding).IsBound() { Do ..Fail("no case is bound to this call") }
}

ClassMethod Fail(pText As %String) [ Private ]
{
	Throw ##class(%Exception.General).%New("ToolFailure", 5001, "Readback.Tools.Impl", pText)
}

/// The result as JSON text no longer than the configured size: the lists give up their last items first, and the
/// result says it was cut. The result stays valid JSON.
ClassMethod Bounded(pObject As %DynamicObject) As %String
{
	Set tConfig = ##class(Readback.Config.AgentTools).Current()
	Set tMax = $Select($IsObject(tConfig):tConfig.ToolResultMaxChars, 1:2000)
	Set tText = pObject.%ToJSON()
	For tKey = "earlier", "passages", "similarCases", "indices" {
		While ($Length(tText) > tMax) && $IsObject(pObject.%Get(tKey)) && (pObject.%Get(tKey).%Size() > 0) {
			Do pObject.%Get(tKey).%Pop()
			Set pObject.truncated = 1
			Set tText = pObject.%ToJSON()
		}
	}
	If $Length(tText) > tMax { Set tText = "{""truncated"":true,""note"":""the result was too large to hand back""}" }
	Quit tText
}

}
