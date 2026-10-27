/// REST endpoint of the product: the run mode and the trace of a decision. Never returns key material.
Class Readback.API.Status Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

XData UrlMap
{
<Routes>
  <Route Url="/status" Method="GET" Call="GetStatus"/>
  <Route Url="/decisions/:controlId" Method="GET" Call="GetDecision"/>
</Routes>
}

ClassMethod GetStatus() As %Status
{
	Set tMode = ##class(Readback.Config.Mode).Current()
	Set tRes = {}
	Set tRes.mode = tMode
	Set tRes.provider = $Select(tMode="live":"openai", 1:"replay")
	Set tRes.model = $Select(tMode="live":##class(Ens.Director).GetAdapterSettingValue("Readback.Agent", "Model"), 1:"fixture")
	Set tRes.promptVersion = ##class(Readback.Triage.Prompt).#Version
	Set tRes.agentTimeoutSeconds = +##class(Ens.Director).GetHostSettingValue("Readback.Triage", "AgentTimeoutSeconds")
	Set tRes.replaySet = ##class(Readback.Replay.Recording).ActiveSet()
	Set tRes.rangesLoaded = ..Count("Readback_Config.Range")
	Set tRes.pricesLoaded = ..Count("Readback_Config.Price")
	Set tSet = tRes.replaySet
	&sql(SELECT COUNT(*) INTO :tRec FROM Readback_Replay.Recording WHERE ReplaySet = :tSet)
	Set tRes.recordingsLoaded = +$Get(tRec)
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
	If SQLCODE '= 0 {
		Set %response.Status = "404 Not Found"
		Write {"error":"no decision recorded for that case id"}.%ToJSON()
		Quit $$$OK
	}
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
	Write tRes.%ToJSON()
	Quit $$$OK
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
