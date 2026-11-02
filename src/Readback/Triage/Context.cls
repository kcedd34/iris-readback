/// Builds the plain text sent to the agent: the case and its value, nothing more. Everything else the agent needs
/// (the earlier results, the change against them, the policy, the sample quality) it asks for through the tools.
Class Readback.Triage.Context
{

/// Earlier results are looked up in the stored lab results: same patient and analyte, collected within
/// 7 days before this result, newest first, at most 3, never the result itself. Used by the history tool.
Parameter LookbackDays = 7;

Parameter MaxEarlier = 3;

ClassMethod CollectedOrNow(pLab As Readback.Msg.LabResult) As %String
{
	Quit $Select(pLab.CollectedAt'="":pLab.CollectedAt, 1:$ZDateTime($Horolog, 3))
}

/// The user text of the agent call. It carries no patient identifier: no tool takes one, and the agent has no use for it.
ClassMethod Build(pLab As Readback.Msg.LabResult, pConv As %DynamicObject = "") As %String
{
	Set tCR = $Char(10)
	Set tText = "Lab result to triage."_tCR
	Set tText = tText_"Case id: "_pLab.MessageControlId_tCR
	Set tText = tText_"Patient age: "_$Select(pLab.AgeYears'="":pLab.AgeYears_" years", 1:"unknown")_tCR
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
	Set tText = tText_"Collected at: "_..CollectedOrNow(pLab)_tCR
	Quit tText
}

/// The earlier results of a patient and analyte, as a list of objects with id, value, unit and collectedAt: collected
/// within LookbackDays before pCollected, newest first, at most pMax (never more than MaxEarlier), never the result itself.
ClassMethod EarlierRows(pPatient As %String, pAnalyte As %String, pControlId As %String, pCollected As %String, pMax As %Integer = {..#MaxEarlier}) As %DynamicArray
{
	Set tRows = []
	If (pMax = "") || (pMax < 1) || (pMax > ..#MaxEarlier) { Set pMax = ..#MaxEarlier }
	Set tH = $ZDateTimeH(pCollected, 3, , , , , , , , "")
	Quit:tH="" tRows
	Set tFrom = $ZDateTime(($Piece(tH, ",", 1) - ..#LookbackDays)_","_$Piece(tH, ",", 2), 3)
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_pMax_" ValueText, Unit, CollectedAt FROM Readback_Msg.LabResult WHERE PatientId = ? AND AnalyteCode = ? AND MessageControlId <> ? AND CollectedAt < ? AND CollectedAt >= ? ORDER BY CollectedAt DESC")
	Quit:$System.Status.IsError(tSC) tRows
	Set tRS = tStmt.%Execute(pPatient, pAnalyte, pControlId, pCollected, tFrom)
	Set tN = 0
	While tRS.%Next() {
		Set tN = tN + 1
		Do tRows.%Push({"id":("earlier-result-"_tN),"value":(tRS.%Get("ValueText")),"unit":(tRS.%Get("Unit")),"collectedAt":(tRS.%Get("CollectedAt"))})
	}
	Quit tRows
}

}
