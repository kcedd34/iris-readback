/// Sends the Visual Trace message of one tool call. This is a side channel and nothing else: it is asynchronous, it never
/// throws, it never returns a status, and a failure to send (the operation is disabled, its queue is full, the call
/// raises) is counted apart and written to the event log, never to the record of the investigation. The decision does not
/// read the count and does not wait for the message, so with the operation switched off the decision is the same.
Class Readback.Agent.TraceEmit
{

/// Sends one message through pHost (a business host: the agent operation or the replay operation).
ClassMethod Send(pHost As %RegisteredObject, pMode As %String, pCaseId As %String, pSeq As %Integer, pTool As %String, pStatus As %String, pDuration As %Integer, pArgs As %String, pSummary As %String)
{
	Try {
		If $IsObject(pHost) {
			Set tMsg = ##class(Readback.Msg.ToolCall).%New()
			Set tMsg.CaseId = pCaseId, tMsg.Seq = pSeq, tMsg.Tool = $Extract(pTool, 1, 50), tMsg.Status = $Extract(pStatus, 1, 20)
			Set tMsg.DurationMs = +pDuration, tMsg.Mode = pMode
			Set tMsg.Arguments = ##class(Readback.Tools.Summary).Args(pArgs), tMsg.Summary = $Extract(pSummary, 1, 200)
			Set tSC = pHost.SendRequestAsync("Readback.Agent.ToolTrace", tMsg, 0)
			If $System.Status.IsError(tSC) { Do ..Fault($System.Status.GetErrorText(tSC)) }
		}
	} Catch ex {
		Do ..Fault(ex.Name_" "_$Extract(ex.Data, 1, 200))
	}
}

/// The recorded tool calls of a replayed investigation, as the same messages labelled replay, in the recorded order.
ClassMethod Replay(pHost As %RegisteredObject, pCaseId As %String, pCallsJson As %String)
{
	Try {
		If pCallsJson '= "" {
			Set tCalls = [].%FromJSON(pCallsJson)
			For i = 0:1:tCalls.%Size()-1 {
				Set tCall = tCalls.%Get(i)
				Set tSummary = ##class(Readback.Tools.Summary).Of(tCall.tool, tCall.status, tCall.result, tCall.reason)
				Do ..Send(pHost, "replay", pCaseId, i + 1, tCall.tool, tCall.status, +tCall.durationMs, tCall.arguments, tSummary)
			}
		}
	} Catch ex {
		Do ..Fault(ex.Name_" "_$Extract(ex.Data, 1, 200))
	}
}

/// A failed send: counted in its own variable, which the investigation record never reads, and written once to the event log.
ClassMethod Fault(pText As %String)
{
	Try {
		Set tCount = $Increment(^||Readback.TraceFaults)
		If tCount = 1 {
			Do ##class(%SYS.System).WriteToConsoleLog("Readback tool trace: a step was not sent: "_##class(Readback.Config.Mode).Redact($Extract(pText, 1, 300)), 0, 1)
		}
	} Catch ex {}
}

}
