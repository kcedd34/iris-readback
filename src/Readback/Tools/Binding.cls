/// The case the agent is working on, fixed by the server before the session starts. No tool takes a patient or case
/// identifier as an argument: each tool reads this binding, so the model cannot even ask for another patient's data
/// (the authorization policy checks again as a second layer).
///
/// Two halves. The triage process publishes the facts of the case under its control id before it calls the agent
/// (Publish). The agent operation, in its own job, binds from the case id in the request text (Bind): it copies the
/// published facts into process-private storage that the tools and the policies read (Get), and clears it when the
/// call ends (Clear).
Class Readback.Tools.Binding
{

/// Where the process leaves the facts of a case for the operation. Killed when the call ends.
Parameter STORE = "^Readback.Bind";

/// Process-private copy that the tools and the policies read.
Parameter LOCAL = "^||Readback.Binding";

/// Leaves the facts of the case for the operation: who and what the case is, the value in both units, the sample
/// quality indices and what the floor decided. pOriginal is the result as received, pEffective the same result in the
/// reference unit of its analyte.
ClassMethod Publish(pOriginal As Readback.Msg.LabResult, pEffective As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult)
{
	Set tIndices = []
	For i = 1:1:pOriginal.SampleIndices.Count() { Do tIndices.%Push(pOriginal.SampleIndices.GetAt(i)) }
	Set tFactor = ""
	If (pOriginal.ValueNumeric '= "") && (pOriginal.ValueNumeric '= 0) && (pEffective.ValueNumeric '= "") {
		Set tFactor = pEffective.ValueNumeric / pOriginal.ValueNumeric
	}
	Set tFacts = {
		"caseId":(pOriginal.MessageControlId),
		"patientId":(pOriginal.PatientId),
		"analyteCode":(pOriginal.AnalyteCode),
		"collectedAt":(##class(Readback.Triage.Context).CollectedOrNow(pOriginal)),
		"originalValue":(pOriginal.ValueText),
		"originalNumeric":(pOriginal.ValueNumeric),
		"originalUnit":(pOriginal.Unit),
		"effectiveValue":(pEffective.ValueText),
		"effectiveNumeric":(pEffective.ValueNumeric),
		"effectiveUnit":(pEffective.Unit),
		"factor":(tFactor),
		"floorSeverity":(+pFloor.Severity),
		"floorRuleId":(pFloor.RuleId),
		"floorNote":(pFloor.Note),
		"sampleIndices":(tIndices)
	}
	Set @(..#STORE_"("""_pOriginal.MessageControlId_""")") = tFacts.%ToJSON()
}

/// Removes what Publish left for a case.
ClassMethod Unpublish(pCaseId As %String)
{
	Kill @(..#STORE_"("""_pCaseId_""")")
}

/// Binds the call to the case named in the request text. Returns an error when the process left no facts for it: the
/// operation then makes no agent call and the case goes to a person.
ClassMethod Bind(pCaseId As %String) As %Status
{
	Do ..Clear()
	If pCaseId = "" { Quit $$$ERROR($$$GeneralError, "no case id in the request") }
	Set tText = $Get(@(..#STORE_"("""_pCaseId_""")"))
	If tText = "" { Quit $$$ERROR($$$GeneralError, "no facts were published for case "_pCaseId) }
	Set tFacts = {}.%FromJSON(tText)
	Set tIter = tFacts.%GetIterator()
	While tIter.%GetNext(.tKey, .tValue) {
		If $IsObject(tValue) { Set tValue = tValue.%ToJSON() }
		Set @(..#LOCAL_"("""_tKey_""")") = tValue
	}
	Set @(..#LOCAL_"(""bound"")") = 1
	Quit $$$OK
}

/// True while a case is bound in this process.
ClassMethod IsBound() As %Boolean
{
	Quit +$Get(@(..#LOCAL_"(""bound"")"))
}

/// One fact of the bound case, or "" when nothing is bound or the fact is unknown.
ClassMethod Get(pField As %String) As %String
{
	Quit $Get(@(..#LOCAL_"("""_pField_""")"))
}

/// The sample quality indices of the bound case as a list of `code=value` strings.
ClassMethod Indices() As %DynamicArray
{
	Set tText = ..Get("sampleIndices")
	Quit:tText="" []
	Quit [].%FromJSON(tText)
}

/// Forgets the bound case in this process.
ClassMethod Clear()
{
	Kill @(..#LOCAL)
}

}
