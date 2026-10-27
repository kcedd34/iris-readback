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

ClassMethod Build(pLab As Readback.Msg.LabResult) As %String
{
	Set tCR = $Char(10)
	Set tCollected = ..CollectedOrNow(pLab)
	Set tText = "Lab result to triage."_tCR
	Set tText = tText_"Case id: "_pLab.MessageControlId_tCR
	Set tText = tText_"Patient: "_pLab.PatientId_$Select(pLab.AgeYears'="":", age "_pLab.AgeYears_" years", 1:", age unknown")_tCR
	Set tText = tText_"Analyte code: "_pLab.AnalyteCode_tCR
	Set tText = tText_"Value: "_pLab.ValueText_$Select(pLab.Unit'="":" "_pLab.Unit, 1:"")_" (current-result)"_tCR
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
	Quit tText
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
