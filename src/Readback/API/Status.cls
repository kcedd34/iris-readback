/// REST endpoint of the product: the run mode and the trace of a decision. Never returns key material.
Class Readback.API.Status Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

XData UrlMap
{
<Routes>
  <Route Url="/status" Method="GET" Call="GetStatus"/>
  <Route Url="/decisions/:controlId" Method="GET" Call="GetDecision"/>
  <Route Url="/indicators" Method="GET" Call="GetIndicators"/>
</Routes>
}

ClassMethod GetStatus() As %Status
{
	Set tMode = ##class(Readback.Config.Mode).Current()
	Set tRes = {}
	Set tRes.mode = tMode
	Set tRes.provider = $Select(tMode="live":"openai", 1:"replay")
	Set tRes.model = $Select(tMode="live":##class(Ens.Director).GetAdapterSettingValue("Readback.Agent", "Model"), 1:##class(Readback.Replay.Recording).ActiveModel())
	Set tRes.promptVersion = ##class(Readback.Triage.Prompt).#Version
	Set tRes.agentTimeoutSeconds = +##class(Ens.Director).GetHostSettingValue("Readback.Triage", "AgentTimeoutSeconds")
	Set tRes.replaySet = ##class(Readback.Replay.Recording).ActiveSet()
	Set tRes.rangesLoaded = ..Count("Readback_Config.Range")
	Set tRes.pricesLoaded = ..Count("Readback_Config.Price")
	Set tSet = tRes.replaySet
	&sql(SELECT COUNT(*) INTO :tRec FROM Readback_Replay.Recording WHERE ReplaySet = :tSet)
	Set tRes.recordingsLoaded = +$Get(tRec)
	Set tRes.budget = ##class(Readback.Budget.Guard).Now(tRes.model)
	Set tRes.retrieval = ##class(Readback.Retrieval.Engine).Snapshot()
	Set tRes.unitComponent = {}
	Do tRes.unitComponent.%Set("registered", ''##class(Readback.Units.Setup).IsRegistered(), "boolean")
	Do tRes.%Set("productionRunning", ''##class(Ens.Director).IsProductionRunning("Readback.Production"), "boolean")
	Write tRes.%ToJSON()
	Quit $$$OK
}

ClassMethod Count(pTable As %String) As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_pTable)
	Quit:tRS.%SQLCODE<0 -1
	Do tRS.%Next()
	Quit +tRS.%GetData(1)
}

ClassMethod GetDecision(pControlId As %String) As %Status
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Trace.Decision WHERE MessageControlId = :pControlId ORDER BY ID DESC)
	If SQLCODE = 100 { Quit ..Fail(..#HTTP404NOTFOUND, "no decision recorded for that case id") }
	If SQLCODE < 0 { Throw ##class(%Exception.General).%New("decision lookup failed", SQLCODE) }
	Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tId)
	Set tRes = {}
	Set tRes.messageControlId = tTrace.MessageControlId, tRes.sessionId = tTrace.SessionId, tRes.mode = tTrace.Mode
	Set tRes.promptVersion = tTrace.PromptVersion, tRes.model = tTrace.Model, tRes.provider = tTrace.Provider
	Set tRes.rawOutput = tTrace.RawOutput
	Do tRes.%Set("schemaValid", ''tTrace.SchemaValid, "boolean")
	Set tRes.failureKind = tTrace.FailureKind, tRes.failureReason = tTrace.FailureReason
	Set tRes.floorSeverity = tTrace.FloorSeverity, tRes.floorNote = tTrace.FloorNote
	Set tRes.agentDecision = tTrace.AgentDecision, tRes.agentSeverity = tTrace.AgentSeverity, tRes.agentConfidence = tTrace.AgentConfidence
	Set tRes.rationale = tTrace.Rationale, tRes.finalSeverity = tTrace.FinalSeverity, tRes.route = tTrace.Route, tRes.divergence = tTrace.Divergence
	Set tRes.inputTokens = tTrace.InputTokens, tRes.outputTokens = tTrace.OutputTokens
	Do tRes.%Set("costKnown", ''tTrace.CostKnown, "boolean")
	If tTrace.CostKnown { Set tRes.costUsd = tTrace.CostUsd }
	Set tRes.latencyMs = tTrace.LatencyMs, tRes.taskId = tTrace.TaskId
	Set tRes.confirmedBy = tTrace.ConfirmedBy
	Do tRes.%Set("readbackMatch", ''tTrace.ReadbackMatch, "boolean")
	Set tRes.reviewedBy = tTrace.ReviewedBy
	Set tRes.originalValue = tTrace.OriginalValue, tRes.originalUnit = tTrace.OriginalUnit
	Set tRes.convertedValue = tTrace.ConvertedValue, tRes.convertedUnit = tTrace.ConvertedUnit, tRes.conversionOutcome = tTrace.ConversionOutcome
	Set tRes.passageIds = ..JsonOrEmpty(tTrace.PassageIds), tRes.caseLabels = ..JsonOrEmpty(tTrace.CaseLabels)
	Set tRes.indexVersion = tTrace.IndexVersion, tRes.retrievalNote = tTrace.RetrievalNote
	Set tRes.budgetState = tTrace.BudgetState, tRes.budgetBasis = tTrace.BudgetBasis
	Set tRes.budgetUsed = tTrace.BudgetUsed, tRes.budgetCeiling = tTrace.BudgetCeiling, tRes.budgetEstimate = tTrace.BudgetEstimate
	Do tRes.%Set("agentCalled", ''tTrace.AgentCalled, "boolean")
	Set tRes.createdAt = tTrace.CreatedAt
	Write tRes.%ToJSON()
	Quit $$$OK
}

/// A stored JSON array text as an array, or an empty array.
ClassMethod JsonOrEmpty(pText As %String) As %DynamicArray
{
	Quit:pText="" []
	Set tOut = []
	Try { Set tOut = [].%FromJSON(pText) } Catch ex { Set tOut = [] }
	Quit tOut
}

ClassMethod GetIndicators() As %Status
{
	Set tFrom = $Get(%request.Data("from", 1)), tTo = $Get(%request.Data("to", 1))
	If '##class(Readback.Trace.Indicators).Valid(tFrom) || '##class(Readback.Trace.Indicators).Valid(tTo) {
		Quit ..Fail(..#HTTP400BADREQUEST, "from and to must be timestamps in the form YYYY-MM-DD hh:mm:ss")
	}
	Write ##class(Readback.Trace.Indicators).Compute(tFrom, tTo).%ToJSON()
	Quit $$$OK
}

/// The only error body: {"error":"<short English text>"}, redacted. No stack, no request data, no header.
ClassMethod ErrorBody(pHttpStatus As %String, pText As %String = "") As %String
{
	Set tCode = +pHttpStatus
	Set tText = $Case(tCode, 400:"bad request", 403:"forbidden", 404:"not found", 405:"method not allowed", :"internal error")
	// 500 never repeats the failure text to the caller: it can hold routine names and values. It goes, redacted, to the console log.
	If (tCode '= 500) && (pText '= "") { Set tText = pText }
	If (tCode = 500) && (pText '= "") { Do ##class(%SYS.System).WriteToConsoleLog("Readback API: "_$Extract(##class(Readback.Config.Mode).Redact(pText), 1, 500), 0, 1) }
	Quit {"error":(##class(Readback.Config.Mode).Redact(tText))}.%ToJSON()
}

ClassMethod Fail(pHttpStatus As %String, pText As %String) As %Status
{
	Set %response.Status = pHttpStatus
	Set %response.ContentType = "application/json"
	Write ..ErrorBody(pHttpStatus, pText)
	Quit $$$OK
}

/// Every error answer of the framework (400, 403, 404, 405 and an uncaught exception as 500) goes through here.
ClassMethod ReportHttpStatusCode(pHttpStatus As %String, pSC As %Status = {$$$OK}) As %Status
{
	Set tText = $Select($System.Status.IsError(pSC):$System.Status.GetErrorText(pSC), 1:"")
	Quit ..Fail(pHttpStatus, tText)
}

/// Creates the web application /readback/api once (password authentication). Idempotent.
ClassMethod EnsureWebApp() As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit:##class(Security.Applications).Exists("/readback/api") $$$OK
	Set tProps("DispatchClass") = "Readback.API.Status"
	Set tProps("NameSpace") = "USER"
	Set tProps("Enabled") = 1
	Set tProps("AutheEnabled") = 32
	Set tProps("Description") = "Readback status and decision trace"
	Quit ##class(Security.Applications).Create("/readback/api", .tProps)
}

}
