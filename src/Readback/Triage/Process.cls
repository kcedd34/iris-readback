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
	Quit ..Route(pRequest, tFinal, tMode, tTrace)
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

/// Sends the routed outcome on. Read-back and review tasks are added with the human step.
Method Route(pLab As Readback.Msg.LabResult, pFinal As Readback.Triage.FinalDecision, pMode As %String, pTrace As Readback.Trace.Decision) As %Status
{
	Set tOutcome = ##class(Readback.Msg.Outcome).%New()
	Set tOutcome.MessageControlId = pLab.MessageControlId, tOutcome.Route = pFinal.Route
	Set tOutcome.FinalSeverity = pFinal.FinalSeverity, tOutcome.Reason = pFinal.Reason, tOutcome.Mode = pMode
	Quit ..SendRequestAsync("Readback.Outbound.OutcomeOperation", tOutcome, 0)
}

Method OnResponse(request As Ens.Request, ByRef response As Ens.Response, callrequest As Ens.Request, callresponse As Ens.Response, pCompletionKey As %String) As %Status
{
	Quit $$$OK
}

}
