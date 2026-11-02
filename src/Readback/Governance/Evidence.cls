/// The traceable-evidence rule, checked on the server: every identifier the agent cites in `evidence` must be
/// `current-result` (the value it was given) or an identifier that a tool returned during this same investigation.
/// A citation that no tool returned is an invented source, so the answer is handled as an invalid answer.
Class Readback.Governance.Evidence
{

/// The identifiers the tool results of this investigation carry (every "id" value, at any depth), as a $List.
ClassMethod Returned(pCalls As %DynamicArray) As %List
{
	Set tIds = ""
	For i = 0:1:pCalls.%Size()-1 {
		Set tCall = pCalls.%Get(i)
		Continue:tCall.status'="ok"
		Try { Do ..Collect({}.%FromJSON(tCall.result), .tIds) } Catch ex {}
	}
	Quit tIds
}

ClassMethod Collect(pNode As %DynamicAbstractObject, ByRef pIds As %List) [ Private ]
{
	If pNode.%IsA("%Library.DynamicArray") {
		For i = 0:1:pNode.%Size()-1 {
			Set tItem = pNode.%Get(i)
			Do:$IsObject(tItem) ..Collect(tItem, .pIds)
		}
		Quit
	}
	Set tIter = pNode.%GetIterator()
	While tIter.%GetNext(.tKey, .tValue) {
		If $IsObject(tValue) {
			Do ..Collect(tValue, .pIds)
		} ElseIf (tKey = "id") && (tValue '= "") && ($ListFind(pIds, tValue) = 0) {
			Set pIds = pIds_$ListBuild(tValue)
		}
	}
}

/// Checks the evidence of a parsed answer against the tool calls. Returns "" when it holds, else the identifiers that
/// no tool returned, comma separated.
ClassMethod Unsupported(pEvidenceJson As %String, pCalls As %DynamicArray) As %String
{
	Set tReturned = ..Returned(pCalls)
	Set tBad = ""
	Set tEvidence = ""
	Try { Set tEvidence = [].%FromJSON(pEvidenceJson) } Catch ex { Set tEvidence = "" }
	If '$IsObject(tEvidence) { Quit "evidence unreadable" }
	For i = 0:1:tEvidence.%Size()-1 {
		Set tId = tEvidence.%Get(i)
		Continue:tId="current-result"
		If $ListFind(tReturned, tId) = 0 { Set tBad = tBad_$Select(tBad="":"", 1:", ")_tId }
	}
	Quit tBad
}

}
