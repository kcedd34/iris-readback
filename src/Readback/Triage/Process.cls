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

	Set tFloor = ##class(Readback.Triage.Floor).Compute(pRequest)
	Set tText = ##class(Readback.Triage.Context).Build(pRequest)
	Set tMode = ##class(Readback.Config.Mode).Current()
	Set tOutcome = ..CallAgent(tText, tMode)
	Set tFinal = ##class(Readback.Triage.Pipeline).Decide(pRequest, tFloor, tOutcome, .tAgent)
	Set tTrace = ..SaveTrace(pRequest, tFloor, tAgent, tFinal, tOutcome, tText, tMode)
	Quit ..Route(pRequest, tFinal, tAgent, tMode, tTrace)
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
	Try {
		Set tSC = ..SendRequestSync(tTarget, tRequest, .tResponse, ..AgentTimeoutSeconds)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Set tOutcome.LatencyMs = $Justify(($ZHorolog - tStart) * 1000, 0, 0)
	If pMode = "live" { Set tOutcome.Model = ##class(Ens.Director).GetAdapterSettingValue(tTarget, "Model") }
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
Method SaveTrace(pLab As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult, pAgent As Readback.Triage.AgentOutput, pFinal As Readback.Triage.FinalDecision, pOutcome As Readback.Triage.AgentOutcome, pText As %String, pMode As %String) As Readback.Trace.Decision
{
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = pLab.MessageControlId
	Set tTrace.SessionId = +$$$JobSessionId
	Set tTrace.Mode = pMode
	Set tTrace.InputText = pText
	Set tTrace.PromptVersion = ##class(Readback.Triage.Prompt).#Version
	Set tTrace.Model = pOutcome.Model
	Set tTrace.Provider = "openai"
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
	Set tTrace.LatencyMs = pOutcome.LatencyMs
	Do tTrace.%Save()
	Quit tTrace
}

/// Opens a read-back or review task when the route needs a person, then logs the outcome.
Method Route(pLab As Readback.Msg.LabResult, pFinal As Readback.Triage.FinalDecision, pAgent As Readback.Triage.AgentOutput, pMode As %String, pTrace As Readback.Trace.Decision) As %Status
{
	If (pFinal.Route = "readback") || (pFinal.Route = "review") {
		Do ..OpenTask(pLab, pFinal, pAgent, pMode, pTrace)
	}
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
