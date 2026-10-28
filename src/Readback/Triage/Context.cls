/// Builds the plain text sent to the agent, including the patient's earlier stored results for the same analyte.
Class Readback.Triage.Context
{

/// Earlier results are looked up in the stored lab results: same patient and analyte, collected within
/// 7 days before this result, newest first, at most 3, never the result itself.
Parameter LookbackDays = 7;

Parameter MaxEarlier = 3;

ClassMethod CollectedOrNow(pLab As Readback.Msg.LabResult) As %String
{
	Quit $Select(pLab.CollectedAt'="":pLab.CollectedAt, 1:$ZDateTime($Horolog, 3))
}

ClassMethod Build(pLab As Readback.Msg.LabResult, pConv As %DynamicObject = "", pRetrieval As Readback.Msg.RetrievalResponse = "") As %String
{
	Set tCR = $Char(10)
	Set tCollected = ..CollectedOrNow(pLab)
	Set tText = "Lab result to triage."_tCR
	Set tText = tText_"Case id: "_pLab.MessageControlId_tCR
	Set tText = tText_"Patient: "_pLab.PatientId_$Select(pLab.AgeYears'="":", age "_pLab.AgeYears_" years", 1:", age unknown")_tCR
	Set tText = tText_"Analyte code: "_pLab.AnalyteCode_tCR
	Set tText = tText_"Value: "_pLab.ValueText_$Select(pLab.Unit'="":" "_pLab.Unit, 1:"")_" (current-result)"_tCR
	If $IsObject(pConv) {
		If pConv.outcome = "converted" {
			Set tText = tText_"Converted value: "_pConv.value_" "_pConv.unit_" (reference unit of the analyte)"_tCR
		} ElseIf pConv.outcome = "not-convertible" {
			Set tText = tText_"Converted value: not available (unit not convertible)"_tCR
		} ElseIf pConv.outcome = "unavailable" {
			Set tText = tText_"Converted value: not available (unit conversion unavailable)"_tCR
		}
	}
	Set tText = tText_"Reference range: "_$Select(pLab.ReferenceRange'="":pLab.ReferenceRange, 1:"not given")_tCR
	Set tText = tText_"Collected at: "_tCollected_tCR
	Set tIndices = ""
	For i = 1:1:pLab.SampleIndices.Count() { Set tIndices = tIndices_$Select(tIndices="":"", 1:", ")_pLab.SampleIndices.GetAt(i) }
	Set tText = tText_"Sample quality indices: "_$Select(tIndices="":"none", 1:tIndices)_tCR
	Set tEarlier = ..Earlier(pLab, tCollected)
	If tEarlier = "" {
		Set tText = tText_"No earlier results for this patient and analyte in the last "_..#LookbackDays_" days."_tCR
	} Else {
		Set tText = tText_"Earlier results for this analyte in the last "_..#LookbackDays_" days, newest first:"_tCR_tEarlier
	}
	If $IsObject(pRetrieval) { Set tText = tText_..RetrievalSection(pRetrieval) }
	Quit tText
}

/// The policy and similar-case sections of the agent text. Retrieval that failed says so; retrieval that found
/// nothing says that instead. The two are different statements.
ClassMethod RetrievalSection(pRetrieval As Readback.Msg.RetrievalResponse) As %String
{
	Set tCR = $Char(10)
	If 'pRetrieval.Available { Quit "Policy and case retrieval is not available for this result."_tCR }
	Set tText = ""
	If pRetrieval.Passages.Count() = 0 {
		Set tText = tText_"No policy passage matched."_tCR
	} Else {
		Set tText = tText_"Policy passages ("_pRetrieval.IndexVersion_"):"_tCR
		For i = 1:1:pRetrieval.Passages.Count() { Set tText = tText_..PassageLine(pRetrieval.Passages.GetAt(i)) }
	}
	If pRetrieval.Cases.Count() = 0 {
		Set tText = tText_"No similar confirmed case."_tCR
	} Else {
		Set tText = tText_"Similar confirmed cases:"_tCR
		For i = 1:1:pRetrieval.Cases.Count() { Set tText = tText_..CaseLine(pRetrieval.Cases.GetAt(i)) }
	}
	Quit tText
}

ClassMethod PassageLine(pItem As Readback.Msg.RetrievalItem) As %String
{
	Quit "["_pItem.Id_"] "_pItem.Text_$Char(10)
}

ClassMethod CaseLine(pItem As Readback.Msg.RetrievalItem) As %String
{
	Quit pItem.Id_": "_pItem.Text_" Decision: "_pItem.Decision_". Route: "_pItem.Route_"."_$Char(10)
}

/// The number of characters each retrieved item adds to the text, as two $Lists, for the budget guard.
ClassMethod ItemChars(pRetrieval As Readback.Msg.RetrievalResponse, Output pPassageChars As %List, Output pCaseChars As %List)
{
	Set pPassageChars = "", pCaseChars = ""
	Quit:'$IsObject(pRetrieval)
	Quit:'pRetrieval.Available
	For i = 1:1:pRetrieval.Passages.Count() { Set pPassageChars = pPassageChars_$ListBuild($Length(..PassageLine(pRetrieval.Passages.GetAt(i)))) }
	For i = 1:1:pRetrieval.Cases.Count() { Set pCaseChars = pCaseChars_$ListBuild($Length(..CaseLine(pRetrieval.Cases.GetAt(i)))) }
}

/// Numbered lines of earlier results, or empty.
ClassMethod Earlier(pLab As Readback.Msg.LabResult, pCollected As %String) As %String
{
	Set tH = $ZDateTimeH(pCollected, 3, , , , , , , , "")
	Quit:tH="" ""
	Set tFrom = $ZDateTime(($Piece(tH, ",", 1) - ..#LookbackDays)_","_$Piece(tH, ",", 2), 3)
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_..#MaxEarlier_" ValueText, Unit, CollectedAt FROM Readback_Msg.LabResult WHERE PatientId = ? AND AnalyteCode = ? AND MessageControlId <> ? AND CollectedAt < ? AND CollectedAt >= ? ORDER BY CollectedAt DESC")
	Quit:$System.Status.IsError(tSC) ""
	Set tRS = tStmt.%Execute(pLab.PatientId, pLab.AnalyteCode, pLab.MessageControlId, pCollected, tFrom)
	Set tLines = "", tN = 0
	While tRS.%Next() {
		Set tN = tN + 1
		Set tLines = tLines_tN_". "_tRS.%Get("ValueText")_$Select(tRS.%Get("Unit")'="":" "_tRS.%Get("Unit"), 1:"")_" collected "_tRS.%Get("CollectedAt")_" (earlier-result-"_tN_")"_$Char(10)
	}
	Quit tLines
}

}
