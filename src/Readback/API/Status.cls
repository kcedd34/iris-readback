/// REST endpoint of the product: the run mode and the trace of a decision. Never returns key material.
Class Readback.API.Status Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

XData UrlMap
{
<Routes>
  <Route Url="/status" Method="GET" Call="GetStatus"/>
  <Route Url="/decisions" Method="GET" Call="GetDecisions"/>
  <Route Url="/decisions/:controlId" Method="GET" Call="GetDecision"/>
  <Route Url="/indicators" Method="GET" Call="GetIndicators"/>
  <Route Url="/alerts" Method="GET" Call="GetAlerts"/>
  <Route Url="/flow" Method="GET" Call="GetFlow"/>
  <Route Url="/flow/samples" Method="GET" Call="GetSamples"/>
  <Route Url="/flow/submit" Method="POST" Call="PostSubmit"/>
  <Route Url="/taskview/:decisionId" Method="GET" Call="GetTaskView"/>
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
	Set tRes.agent = ..AgentBlock()
	Set tRes.unitComponent = {}
	Do tRes.unitComponent.%Set("registered", ''##class(Readback.Units.Setup).IsRegistered(), "boolean")
	Set tRes.alerts = ##class(Readback.Notify.Alerts).Counts()
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
	Set tRes = ..DecisionJson(pControlId)
	If '$IsObject(tRes) { Quit ..Fail(..#HTTP404NOTFOUND, "no decision recorded for that case id") }
	Write tRes.%ToJSON()
	Quit $$$OK
}

/// The detail of the latest decision of a case as an object (the answer of the decisions route), or "" when there is none.
ClassMethod DecisionJson(pControlId As %String) As %DynamicObject
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Trace.Decision WHERE MessageControlId = :pControlId ORDER BY ID DESC)
	Quit:SQLCODE=100 ""
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
	Set tRes.evidence = ##class(Readback.API.Flow).EvidenceList(tTrace.Evidence)
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
	Set tRes.rounds = $Select(tTrace.Rounds'="":+tTrace.Rounds, 1:1), tRes.policyRefusal = tTrace.PolicyRefusal, tRes.evidenceCheck = tTrace.EvidenceCheck
	Set tRes.toolCalls = ##class(Readback.Trace.Rebuild).CallsOf(tTrace)
	Set tRes.notifications = ..Notifications(tTrace.SessionId)
	Set tRes.ruleLines = ..RuleLinesOf(tTrace)
	Quit tRes
}

/// The sentences of the rules that raised the floor of a decision (the value against its limit, the change over its window), or an
/// empty list when the floor is zero or the lab result is no longer stored.
ClassMethod RuleLinesOf(pTrace As Readback.Trace.Decision) As %DynamicArray
{
	Quit:+pTrace.FloorSeverity=0 []
	Set tControlId = pTrace.MessageControlId
	&sql(SELECT TOP 1 ID INTO :tLabId FROM Readback_Msg.LabResult WHERE MessageControlId = :tControlId ORDER BY ID DESC)
	Quit:SQLCODE'=0 []
	Set tLab = ##class(Readback.Msg.LabResult).%OpenId(tLabId)
	Quit:'$IsObject(tLab) []
	Quit ##class(Readback.Trace.TaskText).RuleLines(pTrace, tLab, ##class(Readback.API.Flow).AnalyteName(tControlId))
}

/// The feed of every decision, newest first, for the Decisions screen. A closed field list: the case id and what the product
/// decided, never the patient, the prompt text or the raw output of the model. limit: 50 by default, 200 at most; before: a
/// decision id, for the next page.
ClassMethod GetDecisions() As %Status
{
	Set tLimit = +$Get(%request.Data("limit", 1))
	Set:(tLimit<1) tLimit = 50
	Set:(tLimit>200) tLimit = 200
	Set tBefore = +$Get(%request.Data("before", 1))
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_(tLimit + 1)_" ID FROM Readback_Trace.Decision WHERE (? = 0 OR ID < ?) ORDER BY ID DESC")
	If $System.Status.IsError(tSC) { Quit ..Fail(..#HTTP500INTERNALSERVERERROR, "the decisions could not be read") }
	Set tRS = tStmt.%Execute(tBefore, tBefore)
	Set tItems = [], tN = 0, tMore = 0
	While tRS.%Next() {
		Set tN = tN + 1
		If tN > tLimit { Set tMore = 1  Quit }
		Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tRS.%Get("ID"))
		Do tItems.%Push(..FeedItem(tTrace))
	}
	Set tRes = {"items":(tItems)}
	Do tRes.%Set("more", tMore, "boolean")
	Write tRes.%ToJSON()
	Quit $$$OK
}

/// One decision of the feed. Only the fields of the contract; every free text goes through the same redaction as the other views.
ClassMethod FeedItem(pTrace As Readback.Trace.Decision) As %DynamicObject
{
	Set tItem = {}
	Set tItem.decisionId = +pTrace.%Id()
	Set tItem.controlId = pTrace.MessageControlId
	Set tItem.analyte = ##class(Readback.API.Flow).AnalyteName(pTrace.MessageControlId)
	Set tItem.value = {"text":(pTrace.OriginalValue),"unit":(pTrace.OriginalUnit)}
	Set tItem.decidedAt = pTrace.CreatedAt
	Set tItem.mode = pTrace.Mode
	Set tItem.route = pTrace.Route
	Set tItem.floor = {"severity":(+pTrace.FloorSeverity),"ruleId":(pTrace.FloorRuleId),"note":(##class(Readback.Config.Mode).Redact(pTrace.FloorNote))}
	If pTrace.AgentCalled && (pTrace.AgentDecision '= "") {
		Set tAgent = {"decision":(pTrace.AgentDecision),"severity":(+pTrace.AgentSeverity),"confidence":(pTrace.AgentConfidence)}
		Set tAgent.rationale = ##class(Readback.Config.Mode).Redact($Extract(pTrace.Rationale, 1, 300))
		Set tAgent.evidence = ##class(Readback.API.Flow).EvidenceList(pTrace.Evidence)
	} Else {
		Set tAgent = {"failureKind":($Select(pTrace.AgentCalled:pTrace.FailureKind, 1:"not-called"))}
	}
	Set tItem.agent = tAgent
	Set tItem.final = {"severity":(+pTrace.FinalSeverity)}
	Do tItem.%Set("held", $Select(pTrace.PolicyRefusal'="":1, 1:0), "boolean")
	If pTrace.ConversionOutcome = "converted" {
		Set tItem.conversion = {"original":(pTrace.OriginalValue_" "_pTrace.OriginalUnit),"converted":(##class(Readback.Config.Analyte).Round(##class(Readback.API.Flow).AnalyteCodeOf(pTrace.MessageControlId), pTrace.ConvertedValue)),"unit":(pTrace.ConvertedUnit),"standard":"reference unit of the analyte"}
	}
	Set tCost = {"tokens":(+pTrace.InputTokens + pTrace.OutputTokens),"latencyMs":($Select(pTrace.RecordedLatencyMs'="":+pTrace.RecordedLatencyMs, 1:+pTrace.LatencyMs)),"model":(pTrace.Model)}
	If (pTrace.Mode '= "replay") && pTrace.CostKnown { Set tCost.usd = pTrace.CostUsd } Else { Do tCost.%Set("usd", "", "null") }
	Set tItem.cost = tCost
	Set tItem.rounds = $Select(pTrace.Rounds'="":+pTrace.Rounds, 1:1)
	Set tItem.toolCallCount = +pTrace.ToolCallCount
	Set tItem.toolFailureCount = +pTrace.ToolFailureCount
	Quit tItem
}

/// The notification events of a session, in time order.
ClassMethod Notifications(pSessionId As %Integer) As %DynamicArray
{
	Set tList = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Event, Recipient, EscalationLevel, EventTime, Detail, AlertId FROM Readback_Trace.Notification WHERE SessionId = ? ORDER BY ID", pSessionId)
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("notifications query failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tItem = {"event":(tRS.%Get("Event")), "recipient":(tRS.%Get("Recipient")), "level":(+tRS.%Get("EscalationLevel")), "at":(tRS.%Get("EventTime")), "detail":(tRS.%Get("Detail"))}
		Do:tRS.%Get("AlertId")'="" tItem.%Set("alertId", +tRS.%Get("AlertId"), "number")
		Do tList.%Push(tItem)
	}
	Quit tList
}

/// The flow panel and the read-back task screen (Readback.API.Flow holds the views).
ClassMethod GetFlow() As %Status
{
	Quit ##class(Readback.API.Flow).GetFlow()
}

ClassMethod GetSamples() As %Status
{
	Quit ##class(Readback.API.Flow).GetSamples()
}

ClassMethod PostSubmit() As %Status
{
	Quit ##class(Readback.API.Flow).PostSubmit()
}

ClassMethod GetTaskView(pDecisionId As %String) As %Status
{
	Quit ##class(Readback.API.Flow).GetTaskView(pDecisionId)
}

ClassMethod GetAlerts() As %Status
{
	Write ##class(Readback.Notify.Alerts).Open().%ToJSON()
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
	Set tText = $Case(tCode, 400:"bad request", 403:"forbidden", 404:"not found", 405:"method not allowed", 429:"too many requests", :"internal error")
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
	// The demo builds its messages with Embedded Python in the session of whoever sends: the web application, not the person, holds
	// the service. The role is matched for every user of the application, only while it serves a request, and is never granted to an account.
	If '##class(Security.Roles).Exists("ReadbackGenerator") {
		Set tRole = ##class(Security.Roles).Create("ReadbackGenerator", "Runs the message generator's Python for the Readback web application", "%Service_EmbeddedPython:U")
		Quit:$System.Status.IsError(tRole) tRole
	}
	If ##class(Security.Applications).Exists("/readback/api") {
		Set tSC = ##class(Security.Applications).Get("/readback/api", .tProps)
		Quit:$System.Status.IsError(tSC) tSC
		If (","_$Get(tProps("MatchRoles"))_",") [ ",:ReadbackGenerator," { Quit $$$OK }
		Set tProps("MatchRoles") = $Get(tProps("MatchRoles"))_$Select($Get(tProps("MatchRoles"))="":"", 1:",")_":ReadbackGenerator"
		Quit ##class(Security.Applications).Modify("/readback/api", .tProps)
	}
	Set tProps("DispatchClass") = "Readback.API.Status"
	Set tProps("NameSpace") = "USER"
	Set tProps("Enabled") = 1
	Set tProps("AutheEnabled") = 32
	Set tProps("Description") = "Readback status and decision trace"
	Set tProps("MatchRoles") = ":ReadbackGenerator"
	Quit ##class(Security.Applications).Create("/readback/api", .tProps)
}

/// What the agent is bound by: the iteration limit, the tool call cap, the tools it may call and the policies attached.
ClassMethod AgentBlock() As %DynamicObject
{
	Set tBounds = ##class(Readback.Config.AgentTools).Current()
	Set tRes = {"tools":["get_patient_history","get_delta_assessment","search_policy","get_sample_quality"],"policies":["scope","audit","floor"]}
	If $IsObject(tBounds) {
		Set tRes.maxIterations = tBounds.MaxIterations, tRes.maxToolCalls = tBounds.MaxToolCalls
	}
	Quit tRes
}

}
