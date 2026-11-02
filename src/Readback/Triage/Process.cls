/// Triage business process: orchestration only. Every rule that matters for safety lives in its own class
/// (Floor, AgentOutput, Composer); this class calls them in order, records the trace and routes the case.
Class Readback.Triage.Process Extends Ens.BusinessProcess
{

/// Seconds to wait for the agent before the case goes to human review. The platform's own timeout setting
/// is not honored (docs/probes.md Probe 6), so the limit is enforced on the call.
Property AgentTimeoutSeconds As %Integer [ InitialExpression = 30 ];

Parameter SETTINGS = "AgentTimeoutSeconds:Agent";

Method OnRequest(pRequest As Readback.Msg.LabResult, Output pResponse As Ens.Response) As %Status
{
	Set pResponse = $$$NULLOREF
	// Feature 1 behavior: the lab result is still logged.
	Do ..SendRequestAsync("Readback.Outbound.LogOperation", pRequest, 0)

	// Units first: the floor and the agent see the value in the reference unit of the analyte.
	Set tConv = ..Convert(pRequest)
	Set tEffective = ##class(Readback.Units.Client).Effective(pRequest, tConv)
	Set tFloor = ##class(Readback.Triage.Floor).Compute(tEffective)
	// The floor also holds the change rule: a large move from the patient's earlier results raises it like a limit.
	Do ##class(Readback.Triage.Delta).Apply(pRequest, tEffective, tFloor)
	// The agent gets the case and asks for the rest through its tools (history, change, policy, sample quality).
	Set tText = ##class(Readback.Triage.Context).Build(pRequest, tConv)
	Set tMode = ##class(Readback.Config.Mode).Current()
	// P-7: the budget is decided before the call. A reached ceiling means no call at all. The guard works from
	// the size estimate and the expected rounds; the real token counts of the whole investigation come back from
	// the session statistics after the call.
	Set tBudget = ##class(Readback.Budget.Guard).Check(tText, ..ModelOf(tMode))
	If tBudget.State = "ok" {
		// The server fixes the case before the session: the tools read it, none takes an identifier.
		Do ##class(Readback.Tools.Binding).Publish(pRequest, tEffective, tFloor)
		Set tOutcome = ..CallAgent(tText, tMode)
		Do ##class(Readback.Tools.Binding).Unpublish(pRequest.MessageControlId)
	} Else {
		Set tOutcome = ##class(Readback.Triage.AgentOutcome).%New()
		Set tOutcome.Mode = tMode, tOutcome.Model = ..ModelOf(tMode), tOutcome.AgentCalled = 0
	}
	Set tOutcome.BudgetState = tBudget.State, tOutcome.BudgetBasis = tBudget.Basis, tOutcome.BudgetUsed = tBudget.Used
	Set tOutcome.BudgetCeiling = tBudget.Ceiling, tOutcome.BudgetEstimate = tBudget.EstimatedTokens
	Set tOutcome.ConversionOutcome = tConv.outcome
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(pRequest, tFloor, tOutcome, .tAgent, tEffective)
	Set tTrace = ..SaveTrace(pRequest, tFloor, tAgent, tFinal, tOutcome, tText, tMode, tConv)
	Quit ..Route(pRequest, tFinal, tAgent, tMode, tTrace)
}

/// Converts the value of a result to the reference unit of its analyte through the Java component. Returns a
/// %DynamicObject with outcome, value, unit and message. Any failure of the component is outcome "unavailable":
/// it is logged and never stops the case.
Method Convert(pLab As Readback.Msg.LabResult) As %DynamicObject
{
	Set tKind = ##class(Readback.Units.Client).NeedsConversion(pLab, .tAnalyte)
	If tKind = "skipped" { Quit {"outcome":"skipped","value":"","unit":"","message":""} }
	If tKind = "not-needed" { Quit {"outcome":"not-needed","value":(pLab.ValueText),"unit":(tAnalyte.ReferenceUnit),"message":""} }
	Set tRequest = ##class(Readback.Units.Client).BuildRequest(pLab, tAnalyte)
	Try {
		Set tSC = ..SendRequestSync("Readback.Units", tRequest, .tResponse, 10)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Set tConv = ##class(Readback.Units.Client).ParseResponse($Get(tResponse), tSC)
	If tConv.outcome = "unavailable" { $$$LOGWARNING(tConv.message) }
	Quit tConv
}

/// A JSON array text of the ids (or the trace ids of cases) of a list of retrieved items.
ClassMethod ItemIds(pList As %ListOfObjects, pTraceIds As %Boolean) As %String
{
	Set tArr = []
	For i = 1:1:pList.Count() { Do tArr.%Push($Select(pTraceIds:pList.GetAt(i).TraceId, 1:pList.GetAt(i).Id)) }
	Quit tArr.%ToJSON()
}

/// The model the agent step of the mode uses: the Model setting of the live item, or the model of the active replay set.
Method ModelOf(pMode As %String) As %String
{
	Quit:pMode'="live" ##class(Readback.Replay.Recording).ActiveModel()
	Quit ##class(Ens.Director).GetAdapterSettingValue("Readback.Agent", "Model")
}

/// Sends the text to the agent item of the mode and returns what came back, without judging it.
Method CallAgent(pText As %String, pMode As %String) As Readback.Triage.AgentOutcome
{
	Set tOutcome = ##class(Readback.Triage.AgentOutcome).%New()
	Set tOutcome.Mode = pMode, tOutcome.TimeoutSeconds = ..AgentTimeoutSeconds
	Set tTarget = $Select(pMode="live":"Readback.Agent", 1:"Readback.Agent.Replay")
	Set tRequest = ##class(EnsLib.AI.Messages.TextRequest).%New()
	Set tRequest.TextMessage = ##class(EnsLib.AI.Content.Text).%New()
	Set tRequest.TextMessage.String = pText
	Set tStart = $ZHorolog
	Kill ^Readback.AgentResult(##class(Readback.Agent.ReplayOperation).CaseId(pText))
	// A recording of a failed live call is handed back as that failure, without a request: the replay of a run
	// equals the run, failures included.
	Set tRecording = $Select(pMode="replay":##class(Readback.Agent.ReplayOperation).Find(pText), 1:"")
	If $IsObject(tRecording) { Set tOutcome.ToolCallsJson = tRecording.ToolCallsJson, tOutcome.Rounds = $Select(tRecording.Rounds'="":tRecording.Rounds, 1:1) }
	If $IsObject(tRecording) && (tRecording.FailureKind '= "") {
		Set tOutcome.Model = tRecording.Model, tOutcome.RecordedLatencyMs = tRecording.LatencyMs
		Set tOutcome.LatencyMs = $Justify(($ZHorolog - tStart) * 1000, 0, 0)
		// The tokens a failed investigation spent before it failed are part of the run: the replay states the same cost.
		Set tOutcome.InputTokens = +tRecording.InputTokens, tOutcome.OutputTokens = +tRecording.OutputTokens
		If tRecording.FailureKind = "timeout" {
			Set tOutcome.TimedOut = 1
		} ElseIf tRecording.FailureKind = "provider-error" {
			Set tOutcome.Status = $System.Status.Error(5001, tRecording.FailureReason)
		} ElseIf (tRecording.FailureKind = "tool-failure") || (tRecording.FailureKind = "tool-limit") {
			// The investigation itself failed in the recorded run: the answer, if there was one, was reached with information missing.
			Set tOutcome.ToolFailureKind = tRecording.FailureKind, tOutcome.ToolFailureReason = tRecording.FailureReason
			Set tOutcome.Content = tRecording.AnswerText, tOutcome.InputTokens = +tRecording.InputTokens, tOutcome.OutputTokens = +tRecording.OutputTokens
		} Else {
			Set tOutcome.Content = "", tOutcome.InputTokens = +tRecording.InputTokens, tOutcome.OutputTokens = +tRecording.OutputTokens
		}
		Quit tOutcome
	}
	Try {
		Set tSC = ..SendRequestSync(tTarget, tRequest, .tResponse, ..AgentTimeoutSeconds)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Set tOutcome.LatencyMs = $Justify(($ZHorolog - tStart) * 1000, 0, 0)
	Set tOutcome.Model = ..ModelOf(pMode)
	If pMode = "live" { Do ..ReadInvestigation(pText, tOutcome) }
	// In replay the trace names the model of the recording and keeps the latency of the original call.
	If $IsObject(tRecording) {
		Set:tRecording.Model'="" tOutcome.Model = tRecording.Model
		Set tOutcome.RecordedLatencyMs = tRecording.LatencyMs
	}
	// A call that ran out of time returns without a response and without an error status.
	If $System.Status.IsOK(tSC) && '$IsObject($Get(tResponse)) {
		If tOutcome.LatencyMs >= (..AgentTimeoutSeconds * 1000 - 250) {
			Set tOutcome.TimedOut = 1
		} Else {
			Set tSC = $System.Status.Error(5001, "the agent step returned no response")
		}
	}
	If $System.Status.IsError(tSC) {
		Set tText = ##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(tSC))
		// The platform operation has already written the raw provider text to the event log: clean it.
		Do ##class(Readback.Config.Mode).ScrubEventLog()
		Set tOutcome.Status = $System.Status.Error(5001, tText)
		If (tText [ "imed out") || (tText [ "imeout") { Set tOutcome.TimedOut = 1 }
		Quit tOutcome
	}
	If $IsObject($Get(tResponse)) {
		Set tOutcome.Content = tResponse.Content
		If $IsObject(tResponse.Usage) {
			Set tOutcome.InputTokens = +tResponse.Usage.%Get("prompt_tokens")
			Set tOutcome.OutputTokens = +tResponse.Usage.%Get("completion_tokens")
		}
	}
	Quit tOutcome
}

/// Saves the trace record with every field the decision can be rebuilt from. Never touches the key.
Method SaveTrace(pLab As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult, pAgent As Readback.Triage.AgentOutput, pFinal As Readback.Triage.FinalDecision, pOutcome As Readback.Triage.AgentOutcome, pText As %String, pMode As %String, pConv As %DynamicObject) As Readback.Trace.Decision
{
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = pLab.MessageControlId
	Set tTrace.SessionId = +$$$JobSessionId
	Set tTrace.Mode = pMode
	Set tTrace.InputText = pText
	Set tTrace.PromptVersion = ##class(Readback.Triage.Prompt).#Version
	Set tTrace.Model = pOutcome.Model
	Set tTrace.Provider = $Select(pMode="live":"openai", 1:"replay")
	Set tTrace.RawOutput = pOutcome.Content
	Set tTrace.SchemaValid = pAgent.Valid
	Set tTrace.FailureKind = pAgent.FailureKind
	Set tTrace.FailureReason = pAgent.FailureReason
	Set tTrace.FloorSeverity = pFloor.Severity, tTrace.FloorRuleId = pFloor.RuleId, tTrace.FloorNote = pFloor.Note
	Set tTrace.AgentDecision = pAgent.Decision, tTrace.AgentSeverity = pAgent.Severity
	Set tTrace.AgentConfidence = pAgent.Confidence, tTrace.Rationale = pAgent.Rationale, tTrace.Evidence = pAgent.Evidence
	Set tTrace.FinalSeverity = pFinal.FinalSeverity, tTrace.Route = pFinal.Route, tTrace.Divergence = pFinal.Divergence
	Set tTrace.InputTokens = pOutcome.InputTokens, tTrace.OutputTokens = pOutcome.OutputTokens
	Set tTrace.CostUsd = ##class(Readback.Config.Cost).Compute(pOutcome.Model, pOutcome.InputTokens, pOutcome.OutputTokens, .tKnown)
	Set tTrace.CostKnown = tKnown
	Set tTrace.LatencyMs = pOutcome.LatencyMs, tTrace.RecordedLatencyMs = pOutcome.RecordedLatencyMs
	Set tTrace.OriginalValue = pLab.ValueText, tTrace.OriginalUnit = pLab.Unit
	Set tTrace.ConversionOutcome = pConv.outcome
	If (pConv.outcome = "converted") || (pConv.outcome = "not-needed") { Set tTrace.ConvertedValue = pConv.value, tTrace.ConvertedUnit = pConv.unit }
	Set tTrace.AgentCalled = pOutcome.AgentCalled
	Do ..ApplyInvestigation(tTrace, pOutcome, pAgent)
	Set tTrace.BudgetState = pOutcome.BudgetState, tTrace.BudgetBasis = pOutcome.BudgetBasis, tTrace.BudgetUsed = pOutcome.BudgetUsed
	Set tTrace.BudgetCeiling = pOutcome.BudgetCeiling, tTrace.BudgetEstimate = pOutcome.BudgetEstimate
	Do tTrace.%Save()
	Do ..SaveToolCalls(tTrace, pOutcome)
	Quit tTrace
}

/// What the investigation adds to the trace record: rounds, the tool call counts, the policy refusal, the evidence check,
/// and the policy passages and similar cases the agent asked for (taken from the result of its policy search).
ClassMethod ApplyInvestigation(pTrace As Readback.Trace.Decision, pOutcome As Readback.Triage.AgentOutcome, pAgent As Readback.Triage.AgentOutput)
{
	Set tCalls = $Select(pOutcome.ToolCallsJson'="":[].%FromJSON(pOutcome.ToolCallsJson), 1:[])
	Set pTrace.Rounds = pOutcome.Rounds, pTrace.ToolCallCount = tCalls.%Size()
	Set tFailed = 0
	Set tPassages = [], tCases = [], tCaseTraceIds = []
	For i = 0:1:tCalls.%Size()-1 {
		Set tCall = tCalls.%Get(i)
		If tCall.status '= "ok" { Set tFailed = tFailed + 1  Continue }
		Continue:tCall.tool'="search_policy"
		Try {
			Set tResult = {}.%FromJSON(tCall.result)
			Set pTrace.IndexVersion = tResult.indexVersion
			For j = 0:1:tResult.passages.%Size()-1 { Do tPassages.%Push(tResult.passages.%Get(j).id) }
			For j = 0:1:tResult.similarCases.%Size()-1 {
				Do tCases.%Push(tResult.similarCases.%Get(j).id)
				Do tCaseTraceIds.%Push(tResult.similarCases.%Get(j).traceId)
			}
		} Catch ex {}
	}
	Set pTrace.ToolFailureCount = tFailed
	Set pTrace.PassageIds = tPassages.%ToJSON(), pTrace.CaseLabels = tCases.%ToJSON(), pTrace.CaseTraceIds = tCaseTraceIds.%ToJSON()
	Set pTrace.PolicyRefusal = pAgent.PolicyRefusal, pTrace.EvidenceCheck = pAgent.EvidenceCheck
	Set pTrace.RetrievalNote = $Select(pOutcome.ToolFailureKind'="":pOutcome.ToolFailureReason, 1:"")
}

/// One row per tool call of the decision, in order.
ClassMethod SaveToolCalls(pTrace As Readback.Trace.Decision, pOutcome As Readback.Triage.AgentOutcome)
{
	Quit:pOutcome.ToolCallsJson=""
	Set tCalls = [].%FromJSON(pOutcome.ToolCallsJson)
	For i = 0:1:tCalls.%Size()-1 {
		Set tCall = tCalls.%Get(i)
		Set tRow = ##class(Readback.Trace.ToolCall).%New()
		Set tRow.Decision = pTrace, tRow.Seq = i + 1, tRow.Tool = $Extract(tCall.tool, 1, 50)
		Set tRow.ArgumentsJson = tCall.arguments, tRow.ResultJson = tCall.result, tRow.Status = tCall.status
		Set tRow.Reason = ##class(Readback.Config.Mode).Redact($Extract(tCall.reason, 1, 500)), tRow.DurationMs = +tCall.durationMs
		Do tRow.%Save()
	}
}

/// The result of the investigation the agent operation left for this case: the case totals of tokens, the rounds, the
/// ordered tool calls and the failure the product must act on. The operation writes it even when the call failed.
ClassMethod ReadInvestigation(pText As %String, pOutcome As Readback.Triage.AgentOutcome)
{
	Set tCaseId = ##class(Readback.Agent.ReplayOperation).CaseId(pText)
	Quit:tCaseId=""
	Set tText = $Get(^Readback.AgentResult(tCaseId))
	Kill ^Readback.AgentResult(tCaseId)
	Quit:tText=""
	Set tResult = {}.%FromJSON(tText)
	Set pOutcome.InputTokens = +tResult.promptTokens, pOutcome.OutputTokens = +tResult.completionTokens
	Set pOutcome.Rounds = $Select(tResult.rounds>0:tResult.rounds, 1:1)
	Set pOutcome.ToolCallsJson = tResult.toolCalls.%ToJSON()
	Set pOutcome.ToolFailureKind = tResult.failureKind, pOutcome.ToolFailureReason = tResult.failureReason
}

/// Opens a read-back or review task when the route needs a person, then logs the outcome.
Method Route(pLab As Readback.Msg.LabResult, pFinal As Readback.Triage.FinalDecision, pAgent As Readback.Triage.AgentOutput, pMode As %String, pTrace As Readback.Trace.Decision) As %Status
{
	If (pFinal.Route = "readback") || (pFinal.Route = "review") {
		Do ..OpenTask(pLab, pFinal, pAgent, pMode, pTrace)
	}
	// The alert is an addition to the read-back task and never a condition of it; a review raises none.
	If pFinal.Route = "readback" { Do ##class(Readback.Notify.Raise).ForCase($this, pLab.MessageControlId, pLab.AnalyteCode, pFinal.FinalSeverity) }
	Set tOutcome = ##class(Readback.Msg.Outcome).%New()
	Set tOutcome.MessageControlId = pLab.MessageControlId, tOutcome.Route = pFinal.Route
	Set tOutcome.FinalSeverity = pFinal.FinalSeverity, tOutcome.Reason = pFinal.Reason, tOutcome.Mode = pMode
	Quit ..SendRequestAsync("Readback.Outbound.OutcomeOperation", tOutcome, 0)
}

/// Sends the task request to the role's workflow operation and assigns the task in rotation.
/// When no person holds the role the engine cannot create a task: that is raised as an alert and kept in
/// the trace, never dropped.
Method OpenTask(pLab As Readback.Msg.LabResult, pFinal As Readback.Triage.FinalDecision, pAgent As Readback.Triage.AgentOutput, pMode As %String, pTrace As Readback.Trace.Decision)
{
	Set tReadback = (pFinal.Route = "readback")
	Set tRole = $Select(tReadback:##class(Readback.Workflow.Setup).#Communicators, 1:##class(Readback.Workflow.Setup).#Reviewers)
	Set tPrefix = $Select(pMode="replay":"[replay] ", 1:"")_$Select(tReadback:"Read-back ", 1:"Review ")
	Set tRequest = ##class(EnsLib.Workflow.TaskRequest).%New()
	// %Title is not a display title: the engine reads it as the preferred recipient title, so it stays empty.
	Set tRequest.%Subject = tPrefix_pLab.MessageControlId
	Set tRequest.%Message = ..TaskText(pLab, pFinal, pAgent, pMode, tReadback)
	Set tRequest.%Actions = $Select(tReadback:"Communicated", 1:"Reviewed")
	Set tRequest.%FormFields = $Select(tReadback:"ToldWho,ReadbackValue", 1:"Note")
	Set tRequest.%TaskHandler = $Select(tReadback:"Readback.Workflow.ReadbackTask", 1:"Readback.Workflow.ReviewTask")
	Set tSC = ..SendRequestAsync(tRole, tRequest, 1)
	If $System.Status.IsOK(tSC) {
		Set tSC = ##class(Readback.Workflow.Assigner).Assign(tRole, tPrefix, pLab.MessageControlId, .tTaskId, .tUser)
	}
	If $Get(tTaskId) = "" {
		Set pTrace.TaskId = "UNASSIGNED"
		$$$LOGALERT("No task could be created for "_pLab.MessageControlId_" (route "_pFinal.Route_"): no person holds the role "_tRole_". A person must handle this case.")
	} Else {
		Set pTrace.TaskId = tTaskId
		If $Get(tUser) = "" { $$$LOGWARNING("Task "_tTaskId_" for "_pLab.MessageControlId_" is not assigned to anyone") }
	}
	Do pTrace.%Save()
}

/// The English text a person sees in the task.
ClassMethod TaskText(pLab As Readback.Msg.LabResult, pFinal As Readback.Triage.FinalDecision, pAgent As Readback.Triage.AgentOutput, pMode As %String, pReadback As %Boolean) As %String
{
	Set tText = $Select(pReadback:"Read this critical result back to the clinician you tell, then enter whom you told and the value you repeated.", 1:"This result needs a person to look at it before anything is released.")
	Set tText = tText_" Value: "_pLab.ValueText_$Select(pLab.Unit'="":" "_pLab.Unit, 1:"")_" ("_pLab.AnalyteCode_") for patient "_pLab.PatientId_"."
	Set tText = tText_" Why: "_pFinal.Reason_"."
	If pAgent.Valid {
		Set tText = tText_" Agent: "_pAgent.Decision_", severity "_pAgent.Severity_", confidence "_pAgent.Confidence_". "_pAgent.Rationale
		If pAgent.Evidence '= "" { Set tText = tText_" Evidence: "_pAgent.Evidence_"." }
		If (pAgent.Decision = "RECOLLECT") { Set tText = tText_" The agent suggests a new sample because of the sample quality; this is a recommendation, the value stays critical until a person decides." }
	} ElseIf pAgent.FailureReason '= "" {
		Set tText = tText_" The agent gave no usable answer: "_pAgent.FailureReason_"."
	}
	Set tIndices = ""
	For i = 1:1:pLab.SampleIndices.Count() { Set tIndices = tIndices_$Select(tIndices="":"", 1:", ")_pLab.SampleIndices.GetAt(i) }
	If tIndices '= "" { Set tText = tText_" Sample quality: "_tIndices_"." }
	If pFinal.Divergence '= "" { Set tText = tText_" Note: "_pFinal.Divergence_"." }
	If pMode = "replay" { Set tText = tText_" This run is a replay: the agent answer comes from a stored recording, not from a live provider." }
	Quit tText
}

Method OnResponse(request As Ens.Request, ByRef response As Ens.Response, callrequest As Ens.Request, callresponse As Ens.Response, pCompletionKey As %String) As %Status
{
	Quit $$$OK
}

}
