/// A stored agent answer for one case, used by replay mode. Source says whether it is a hand-authored
/// fixture or a real recorded answer; the trace shows it.
Class Readback.Replay.Recording Extends %Persistent
{

Property ReplaySet As %String(MAXLEN = 50) [ InitialExpression = "default", Required ];

Property MessageControlId As %String(MAXLEN = 50) [ Required ];

Property PromptVersion As %String(MAXLEN = 50) [ Required ];

/// The agent answer exactly as it would arrive from the provider (JSON text).
Property AnswerText As %String(MAXLEN = "");

Property Model As %String(MAXLEN = 100);

Property InputTokens As %Integer;

Property OutputTokens As %Integer;

/// The latency in milliseconds of the real call the recording was taken from. Empty for a row without one.
Property LatencyMs As %Integer;

Property Source As %String(VALUELIST = ",fixture,recorded") [ InitialExpression = "fixture" ];

Index KeyIdx On (ReplaySet, MessageControlId, PromptVersion) [ Unique ];

/// Name of the active replay set (default "default").
ClassMethod ActiveSet() As %String
{
	Quit $Get(^Readback("replaySet"), "default")
}

/// Selects the active replay set.
ClassMethod Activate(pSetName As %String) As %Status
{
	Set ^Readback("replaySet") = pSetName
	Quit $$$OK
}

/// The model named by the recordings of the active set, or "replay" when the set is empty. A case with no recording is
/// traced with this name, so a run of one set carries one model name.
ClassMethod ActiveModel() As %String
{
	Set tSet = ..ActiveSet()
	&sql(SELECT TOP 1 Model INTO :tModel FROM Readback_Replay.Recording WHERE ReplaySet = :tSet AND Model IS NOT NULL AND Model <> '')
	Quit:SQLCODE<0 "replay"
	Quit $Select(SQLCODE=0:tModel, 1:"replay")
}

/// Finds the recording of a case in the active set. Returns the object or "" when there is none.
ClassMethod Lookup(pControlId As %String, pPromptVersion As %String) As Readback.Replay.Recording
{
	Set tId = ..KeyIdxExists(..ActiveSet(), pControlId, pPromptVersion, .tFound)
	Quit:'tId ""
	Quit ..%OpenId(tFound)
}

/// Replaces every recording of the sets present in a JSON Lines file with the file's rows.
ClassMethod LoadFile(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Quit:'##class(%File).Exists(pFile) $$$ERROR($$$GeneralError, "Recordings file not found: "_pFile)
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$$$ISERR(tSC) tSC
	Kill tRows, tSets
	Set tLine = 0, tRows = 0, tBadLine = 0, tBadLatency = 0
	While 'tStream.AtEnd {
		Set tText = $ZStrip(tStream.ReadLine(), "<>W")
		Set tLine = tLine + 1
		Continue:tText=""
		Kill tObj
		Try {
			Set tObj = {}.%FromJSON(tText)
		} Catch ex {
			Set tBadLine = tLine
		}
		If tBadLine { Quit }
		Set tSet = tObj.replaySet
		Set:tSet="" tSet = "default"
		Set tSets(tSet) = 1
		Set tRows($Increment(tRows)) = tObj
		If tObj.%IsDefined("latencyMs") && (tObj.latencyMs '= "") && ((tObj.latencyMs '= +tObj.latencyMs) || (tObj.latencyMs < 0) || (tObj.latencyMs '= (tObj.latencyMs \ 1))) { Set tBadLatency = tRows }
	}
	If tBadLine Quit $$$ERROR($$$GeneralError, "Recordings file line "_tBadLine_" is not valid JSON")
	If tBadLatency Quit $$$ERROR($$$GeneralError, "Recordings file row "_tBadLatency_": latencyMs must be a non-negative integer")
	TStart
	Set tSet = ""
	For { Set tSet = $Order(tSets(tSet))  Quit:tSet=""
		&sql(DELETE FROM Readback_Replay.Recording WHERE ReplaySet = :tSet)
	}
	For i = 1:1:tRows {
		Set tObj = tRows(i)
		If (tObj.messageControlId = "") || (tObj.promptVersion = "") || (tObj.answer = "") {
			TRollback
			Quit
		}
		Set tRec = ..%New()
		Set tRec.ReplaySet = $Select(tObj.replaySet'="":tObj.replaySet, 1:"default")
		Set tRec.MessageControlId = tObj.messageControlId
		Set tRec.PromptVersion = tObj.promptVersion
		Set tRec.AnswerText = tObj.answer
		Set tRec.Model = tObj.model
		Set tRec.InputTokens = tObj.inputTokens
		Set tRec.OutputTokens = tObj.outputTokens
		Set tRec.LatencyMs = $Select(tObj.%IsDefined("latencyMs"):tObj.latencyMs, 1:"")
		Set tRec.Source = $Select(tObj.source'="":tObj.source, 1:"fixture")
		Set tSC = tRec.%Save()
		If $$$ISERR(tSC) { TRollback  Quit }
		Set pCount = pCount + 1
	}
	If $$$ISERR(tSC) Quit tSC
	If pCount '= tRows { Quit $$$ERROR($$$GeneralError, "A recording row is missing messageControlId, promptVersion or answer") }
	TCommit
	Quit $$$OK
}

Storage Default
{
<Data name="RecordingDefaultData">
<Value name="1">
<Value>ReplaySet</Value>
</Value>
<Value name="2">
<Value>MessageControlId</Value>
</Value>
<Value name="3">
<Value>PromptVersion</Value>
</Value>
<Value name="4">
<Value>AnswerText</Value>
</Value>
<Value name="5">
<Value>Model</Value>
</Value>
<Value name="6">
<Value>InputTokens</Value>
</Value>
<Value name="7">
<Value>OutputTokens</Value>
</Value>
<Value name="8">
<Value>Source</Value>
</Value>
<Value name="9">
<Value>LatencyMs</Value>
</Value>
</Data>
<DataLocation>^Readback.Replay.RecordingD</DataLocation>
<DefaultData>RecordingDefaultData</DefaultData>
<IdLocation>^Readback.Replay.RecordingD</IdLocation>
<IndexLocation>^Readback.Replay.RecordingI</IndexLocation>
<StreamLocation>^Readback.Replay.RecordingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
