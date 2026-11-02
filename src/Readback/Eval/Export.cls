/// Exports the trace of a run for the evaluation report and for the recordings: one JSON line per decision row.
/// The file never holds the input text, and the text it does hold passes through the redaction of credentials.
Class Readback.Eval.Export
{

/// Writes the rows whose message id starts with pMessageIdPrefix (all rows when empty) to pFile, oldest first.
/// latencyMs is the recorded latency in replay and the measured one in live, so the same report comes from both.
ClassMethod Rows(pFile As %String, pMessageIdPrefix As %String = "", Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tStream.TranslateTable = "UTF8"
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$System.Status.IsError(tSC) tSC
	Set tSQL = "SELECT ID, Rounds, ToolCallCount, ToolFailureCount, PolicyRefusal, EvidenceCheck, MessageControlId, Mode, Model, PromptVersion, AgentCalled, SchemaValid, FailureKind, FailureReason, FloorSeverity, AgentDecision, AgentSeverity, FinalSeverity, Route, Divergence, InputTokens, OutputTokens, CostUsd, CostKnown, LatencyMs, RecordedLatencyMs, RawOutput FROM Readback_Trace.Decision"
	If pMessageIdPrefix '= "" { Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL_" WHERE MessageControlId %STARTSWITH ? ORDER BY ID", pMessageIdPrefix) }
	Else { Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL_" ORDER BY ID") }
	Quit:tRS.%SQLCODE<0 $System.Status.Error(5001, "the trace could not be read (SQLCODE "_tRS.%SQLCODE_")")
	While tRS.%Next() {
		Set tObj = {}
		Set tObj.messageControlId = tRS.%Get("MessageControlId")
		Set tObj.mode = tRS.%Get("Mode"), tObj.model = tRS.%Get("Model"), tObj.promptVersion = tRS.%Get("PromptVersion")
		Do tObj.%Set("agentCalled", +tRS.%Get("AgentCalled"), "boolean"), tObj.%Set("schemaValid", +tRS.%Get("SchemaValid"), "boolean")
		Set tObj.failureKind = ##class(Readback.Config.Mode).Redact(tRS.%Get("FailureKind"))
		Set tObj.failureReason = ##class(Readback.Config.Mode).Redact(tRS.%Get("FailureReason"))
		Set tObj.floorSeverity = +tRS.%Get("FloorSeverity")
		Set tObj.agentDecision = tRS.%Get("AgentDecision")
		Do:tRS.%Get("AgentSeverity")'="" tObj.%Set("agentSeverity", +tRS.%Get("AgentSeverity"), "number")
		Set tObj.finalSeverity = +tRS.%Get("FinalSeverity"), tObj.route = tRS.%Get("Route")
		Set tObj.divergence = ##class(Readback.Config.Mode).Redact(tRS.%Get("Divergence"))
		Set tObj.inputTokens = +tRS.%Get("InputTokens"), tObj.outputTokens = +tRS.%Get("OutputTokens")
		Set tObj.costUsd = +tRS.%Get("CostUsd")
		Do tObj.%Set("costKnown", +tRS.%Get("CostKnown"), "boolean")
		Set tLatency = $Select((tRS.%Get("Mode")="replay") && (tRS.%Get("RecordedLatencyMs")'=""):tRS.%Get("RecordedLatencyMs"), 1:tRS.%Get("LatencyMs"))
		Do:tLatency'="" tObj.%Set("latencyMs", +tLatency, "number")
		Set tObj.rawOutput = ##class(Readback.Config.Mode).Redact(tRS.%Get("RawOutput"))
		// The investigation: rounds, how many calls and how many did not succeed, the floor policy's refusal, the evidence check, and the calls themselves in order.
		Set tObj.rounds = $Select(tRS.%Get("Rounds")'="":+tRS.%Get("Rounds"), 1:1)
		Set tObj.toolCallCount = +tRS.%Get("ToolCallCount"), tObj.toolFailureCount = +tRS.%Get("ToolFailureCount")
		Set tObj.policyRefusal = ##class(Readback.Config.Mode).Redact(tRS.%Get("PolicyRefusal")), tObj.evidenceCheck = tRS.%Get("EvidenceCheck")
		Set tObj.toolCalls = ##class(Readback.Trace.Rebuild).CallsOf(##class(Readback.Trace.Decision).%OpenId(tRS.%Get("ID")))
		Do tStream.WriteLine(tObj.%ToJSON())
		Set pCount = pCount + 1
	}
	Quit tStream.%Save()
}

}
