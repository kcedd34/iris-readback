/// Replay of a recorded agent answer. It takes the same request and returns the same response type as the
/// live agent item, so everything after the agent step is identical in both modes. The case is found by the
/// case id in the request text and the prompt version.
Class Readback.Agent.ReplayOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnTextRequest(pRequest As EnsLib.AI.Messages.TextRequest, Output pResponse As EnsLib.AI.Messages.LLMResponse) As %Status
{
	Set pResponse = $$$NULLOREF
	Set tRecording = ..Find($Select($IsObject(pRequest.TextMessage):pRequest.TextMessage.String, 1:""))
	If '$IsObject(tRecording) { Quit $System.Status.Error(5001, "no recorded answer") }
	Set pResponse = ##class(EnsLib.AI.Messages.LLMResponse).%New()
	Set pResponse.Content = tRecording.AnswerText
	Set pResponse.Usage = {"prompt_tokens":(+tRecording.InputTokens), "completion_tokens":(+tRecording.OutputTokens), "total_tokens":(+tRecording.InputTokens + +tRecording.OutputTokens)}
	Quit $$$OK
}

/// The recording for the case named in the text, or "".
ClassMethod Find(pText As %String) As Readback.Replay.Recording
{
	Set tCaseId = ..CaseId(pText)
	Quit:tCaseId="" ""
	Quit ##class(Readback.Replay.Recording).Lookup(tCaseId, ##class(Readback.Triage.Prompt).#Version)
}

/// The value after "Case id: " on its own line.
ClassMethod CaseId(pText As %String) As %String
{
	Set tPos = $Find(pText, "Case id: ")
	Quit:'tPos ""
	Set tRest = $Extract(pText, tPos, *)
	Quit $ZStrip($Piece($Piece(tRest, $Char(10), 1), $Char(13), 1), "<>W")
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="EnsLib.AI.Messages.TextRequest">
    <Method>OnTextRequest</Method>
  </MapItem>
</MapItems>
}

}
