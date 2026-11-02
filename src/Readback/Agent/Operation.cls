/// The agent step of the production, as a thin layer over the platform's own agent operation. It does what the native
/// operation cannot: it binds the case on the server before the session starts (no tool takes an identifier), sets the
/// iteration limit on every session (the loop has no bound of its own and outlives the caller's timeout), and after the
/// call reads the session's statistics and exported history to give the true tokens of the whole investigation and the
/// ordered tool calls, including the ones that failed (docs/probes.md, Probe 15).
/// This is the only code that creates an agent session.
Class Readback.Agent.Operation Extends EnsLib.AI.Agent.PassthroughOperation
{

Method handleText(text As %VarString, Output llmresponse As %AI.LLM.Response, session As %AI.Agent.Session = "") As %Status [ Internal ]
{
	Set tCaseId = ##class(Readback.Agent.ReplayOperation).CaseId(text)
	Set tBounds = ##class(Readback.Config.AgentTools).Current()
	If '$IsObject(tBounds) { Quit $System.Status.Error(5001, "the agent bounds are not loaded; no agent call is made") }
	Set tSC = ##class(Readback.Tools.Binding).Bind(tCaseId)
	Quit:$System.Status.IsError(tSC) tSC
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Set %ReadbackHost = $This
	Set tSession = ""
	Set tBefore = {"prompt":0,"completion":0,"rounds":0,"toolCalls":0}
	Try {
		// The limit is set here and nowhere else: a session without it can loop for as long as the provider answers.
		Do ..Adapter.SessionConfig.%Set("max_iterations", tBounds.MaxIterations, "number")
		Set tSession = ..Adapter.Agent.CreateSession(..Adapter.SessionConfig)
		Set tBefore = ..Totals(tSession)
		Set tSC = ##super(text, .llmresponse, tSession)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Do ..Collect(tCaseId, tSession, tBefore, tSC, .llmresponse)
	Kill %ReadbackHost
	Do ##class(Readback.Tools.Binding).Clear()
	Do ##class(Readback.Governance.AuditPolicy).Reset()
	Quit tSC
}

/// The session statistics as an object with prompt, completion, rounds and toolCalls.
ClassMethod Totals(pSession As %AI.Agent.Session) As %DynamicObject
{
	Set tTotals = {"prompt":0,"completion":0,"rounds":0,"toolCalls":0}
	Quit:'$IsObject(pSession) tTotals
	Try {
		Set tStats = pSession.GetStats()
		Set tTotals.prompt = +tStats."total_prompt_tokens", tTotals.completion = +tStats."total_completion_tokens"
		Set tTotals.rounds = +tStats."total_interactions", tTotals.toolCalls = +tStats."total_tool_calls"
	} Catch ex {}
	Quit tTotals
}

/// After the call: the true tokens (statistics after minus before, not the response usage, which is the last round
/// only), the ordered tool calls from the exported history merged with the audit entries, and the failure the product
/// must act on. Left for the triage process under the case id.
Method Collect(pCaseId As %String, pSession As %AI.Agent.Session, pBefore As %DynamicObject, pStatus As %Status, ByRef pResponse As %AI.LLM.Response)
{
	Set tResult = {"promptTokens":0,"completionTokens":0,"rounds":0,"toolCalls":[],"failureKind":"","failureReason":""}
	Try {
		If $IsObject(pSession) {
			Set tAfter = ..Totals(pSession)
			Set tResult.promptTokens = tAfter.prompt - pBefore.prompt, tResult.completionTokens = tAfter.completion - pBefore.completion
			Set tResult.rounds = tAfter.rounds - pBefore.rounds
			Set tCalls = ##class(Readback.Agent.History).Calls(pSession.Export())
			Set tResult.toolCalls = ..Merge(tCalls, ##class(Readback.Governance.AuditPolicy).Entries())
			// The response's usage holds the last round only: replace it with the case total.
			If $IsObject($Get(pResponse)) {
				Set pResponse.Usage = {"prompt_tokens":(tResult.promptTokens),"completion_tokens":(tResult.completionTokens),"total_tokens":(tResult.promptTokens + tResult.completionTokens)}
			}
			Set tFailure = ##class(Readback.Agent.History).FirstFailure(tResult.toolCalls)
			If $IsObject(tFailure) {
				Set tResult.failureKind = "tool-failure"
				Set tResult.failureReason = $Extract("tool "_tFailure.tool_" "_tFailure.status_": "_tFailure.reason, 1, 300)
			}
		}
		If $System.Status.IsError(pStatus) {
			Set tText = $System.Status.GetErrorText(pStatus)
			If tText [ "MaxIterationsReached" {
				Set tResult.failureKind = "tool-limit", tResult.failureReason = "the investigation reached its limit of rounds"
			} ElseIf tText [ "LoopDetected" {
				// The platform's own stall detection: the agent kept asking for the same thing and learned nothing new.
				Set tResult.failureKind = "tool-limit", tResult.failureReason = "the investigation stalled, repeating the same calls"
			}
		}
		If +$Get(^||Readback.AuditFaults) > 0 && (tResult.failureKind = "") {
			Set tResult.failureKind = "tool-failure", tResult.failureReason = "the audit policy failed on a call"
		}
	} Catch ex {
		Set tResult.failureKind = "tool-failure", tResult.failureReason = "the investigation record could not be read"
	}
	Set ^Readback.AgentResult(pCaseId) = tResult.%ToJSON()
}

/// The history's calls with the audit entry of the same tool, in order, for the duration and the policy's reason.
ClassMethod Merge(pCalls As %DynamicArray, pAudit As %DynamicArray) As %DynamicArray
{
	Set tUsed = ""
	For i = 0:1:pCalls.%Size()-1 {
		Set tCall = pCalls.%Get(i)
		Set tCall.durationMs = 0
		For j = 0:1:pAudit.%Size()-1 {
			Continue:$Data(tUsed(j))
			Set tEntry = pAudit.%Get(j)
			Continue:tEntry.tool'=tCall.tool
			Set tUsed(j) = 1
			Set tCall.durationMs = tEntry.durationMs
			If (tCall.status = "ok") && (tEntry.status '= "ok") { Set tCall.status = tEntry.status, tCall.reason = tEntry.reason }
			Set:tCall.reason="" tCall.reason = tEntry.reason
			Quit
		}
	}
	Quit pCalls
}

}
