/// The tools of the read-only MCP server. Every method reads and returns JSON text; none writes anything, none takes a patient identifier,
/// and none confirms a read-back, closes an alert or completes a task: an AI assistant never closes a critical result, because the read-back is
/// the act a person must do (P-4). The answers carry what the public feed of the panel carries, and nothing that names a patient.
Class Readback.MCP.Impl
{

/// A case id as the panel shows it, never a patient identifier.
Parameter CaseIdPattern = "^[A-Za-z0-9._-]{1,50}$";

/// The resource the caller must hold. Checked by every tool before it reads anything, whatever the platform's own authorization does.
Parameter Resource = "Readback_MCP";

/// Refuses the call unless the current user holds the Readback_MCP resource. The first line of every tool.
ClassMethod Authorize() [ Private ]
{
	If '$System.Security.Check(..#Resource, "USE") {
		Do ..Fail("not authorized: the account "_$Username_" does not hold the "_..#Resource_" resource, which the read-only tools require")
	}
}

/// The critical results that wait for a person to repeat the value, with who they are assigned to and the state of their alert.
ClassMethod ListPendingCriticals() As %String
{
	Do ..Authorize()
	Set tTotal = 0
	Set tList = ##class(Readback.API.Flow).Waiting(.tTotal)
	Quit ..Out({"count":(tTotal),"pending":(tList),"note":"These critical results wait for a person to repeat the value. This server cannot confirm a read-back."})
}

/// An explanation of one decision, built from its trace record: the rule, the agent's answer, the composition, the tool calls in order and
/// what a person did. No model is asked: the sentences come from the record.
ClassMethod ExplainDecision(controlId As %String) As %String
{
	Do ..Authorize()
	If '$Match($Get(controlId), ..#CaseIdPattern) { Do ..Fail("controlId must be a case id such as RB2026-00001-S1") }
	Set tD = ##class(Readback.API.Status).DecisionJson(controlId)
	If '$IsObject(tD) { Do ..Fail("no decision recorded for that case id") }
	Set tLines = []
	Do tLines.%Push("Rule floor "_tD.floorSeverity_": "_$Select(tD.ruleLines.%Size()>0:..Join(tD.ruleLines), tD.floorNote'="":tD.floorNote, 1:"no rule raised the floor")_".")
	If tD.agentCalled {
		If tD.agentDecision '= "" {
			Do tLines.%Push("The agent answered "_tD.agentDecision_" with severity "_tD.agentSeverity_" and "_tD.agentConfidence_" confidence: "_tD.rationale)
		} Else {
			Do tLines.%Push("The agent gave no usable answer"_$Select(tD.failureReason'="":": "_tD.failureReason, 1:"")_".")
		}
	} Else {
		Do tLines.%Push("The agent was not called"_$Select(tD.failureReason'="":": "_tD.failureReason, 1:"")_".")
	}
	Do tLines.%Push("The composition took the higher of the floor and the agent: final severity "_tD.finalSeverity_", route "_tD.route_$Select(tD.divergence'="":". Divergence: "_tD.divergence, 1:"")_".")
	If tD.policyRefusal '= "" { Do tLines.%Push("Floor policy: "_tD.policyRefusal) }
	Set tCalls = []
	Set tI = tD.toolCalls.%GetIterator()
	While tI.%GetNext(.tK, .tCall) { Do tCalls.%Push({"seq":(tCall.seq),"tool":(tCall.tool),"status":(tCall.status),"durationMs":(tCall.durationMs)}) }
	Do tLines.%Push(tCalls.%Size()_" tool calls, in order, with their time, are in the trace record"_$Select(tD.evidenceCheck'="":"; evidence check: "_tD.evidenceCheck, 1:"")_".")
	Set tHuman = $Select(tD.confirmedBy'="":"A person confirmed the read-back ("_tD.confirmedBy_").", tD.reviewedBy'="":"A person completed the review ("_tD.reviewedBy_").", tD.route="readback":"Waiting for a person to repeat the value in the read-back.", tD.route="review":"Waiting for a person to review it, or reviewed without a recorded person.", 1:"No human step was needed.")
	Do tLines.%Push(tHuman)
	Quit ..Out({"controlId":(tD.messageControlId),"route":(tD.route),"finalSeverity":(tD.finalSeverity),"floorSeverity":(tD.floorSeverity),"mode":(tD.mode),"model":(tD.model),"promptVersion":(tD.promptVersion),"explanation":(tLines),"toolCalls":(tCalls),"evidence":(tD.evidence),"sessionId":(tD.sessionId)})
}

/// The measured evaluation: the confusion matrices, silenced and missed criticals, cost and latency, per model, from data/eval/report.json.
ClassMethod ReadEvaluation() As %String
{
	Do ..Authorize()
	Set tReport = ..File("report.json")
	Set tOut = {"source":"data/eval/report.json","header":(tReport.header),"models":{}}
	Set tI = tReport.models.%GetIterator()
	While tI.%GetNext(.tName, .tModel) {
		Set tOne = {}
		For tKey = "matrixFinal", "matrixAgent", "silencedCriticals", "missedCriticals", "downgradeAttempts", "costPerThousandUsd", "latencyP50Ms", "latencyP95Ms", "reviewRate", "toolCallsPerResult", "invalidRate", "releaseGuardHolds" {
			Do tOne.%Set(tKey, tModel.%Get(tKey))
		}
		Do tOut.models.%Set(tName, tOne)
	}
	Quit ..Out(tOut)
}

/// The ablation: which layer keeps a critical from being released, from data/eval/ablation.json.
ClassMethod ReadAblation() As %String
{
	Do ..Authorize()
	Set tAblation = ..File("ablation.json")
	Do tAblation.%Remove("origin")
	Set tAblation.source = "data/eval/ablation.json"
	Quit ..Out(tAblation)
}

/// A JSON file of the evaluation folder as an object.
ClassMethod File(pName As %String) As %DynamicObject [ Private ]
{
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(##class(Readback.Config.Paths).Data()_"/eval/"_pName)
	If $System.Status.IsError(tSC) || (tStream.Size = 0) { Do ..Fail("the evaluation file "_pName_" is not available") }
	Quit {}.%FromJSON(tStream)
}

ClassMethod Join(pLines As %DynamicArray) As %String [ Private ]
{
	Set tText = "", tI = pLines.%GetIterator()
	While tI.%GetNext(.tK, .tLine) { Set tText = tText_$Select(tText="":"", 1:" ")_tLine }
	Quit tText
}

/// The JSON text of an answer, with anything shaped like a patient identifier of the synthetic data taken out.
ClassMethod Out(pObject As %DynamicAbstractObject) As %String
{
	Set tMatcher = ##class(%Regex.Matcher).%New("SYN[0-9]{6,}", pObject.%ToJSON())
	Quit tMatcher.ReplaceAll("[removed]")
}

ClassMethod Fail(pText As %String) [ Private ]
{
	Throw ##class(%Exception.General).%New("ToolFailure", 5001, "Readback.MCP.Impl", pText)
}

}
