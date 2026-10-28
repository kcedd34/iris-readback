/// The one function that writes a lab result as text for retrieval, for queries and for stored cases.
/// It reads the analyte, the value and unit, the age, the sample quality indices and the values of earlier
/// results. It never reads the patient id, the message id, a name, a date of birth or any free text, so
/// nothing indexed or sent for a search can identify a person. The patient id is used only as a lookup key.
Class Readback.Retrieval.Describe
{

/// <Analyte name> <value> <unit>, <age group>, <sample indices or "no sample quality problem">, <earlier results or "no earlier results">
ClassMethod Text(pLab As Readback.Msg.LabResult) As %String
{
	Set tName = ..AnalyteName(pLab.AnalyteCode)
	Set tText = tName_" "_pLab.ValueText_$Select(pLab.Unit'="":" "_pLab.Unit, 1:"")
	Set tText = tText_", "_##class(Readback.Triage.Floor).AgeGroup(pLab.AgeYears)
	Set tIndices = ""
	For i = 1:1:pLab.SampleIndices.Count() { Set tIndices = tIndices_$Select(tIndices="":"", 1:" ")_pLab.SampleIndices.GetAt(i) }
	Set tText = tText_", "_$Select(tIndices="":"no sample quality problem", 1:"sample indices "_tIndices)
	Set tEarlier = ..EarlierSummary(pLab)
	Set tText = tText_", "_$Select(tEarlier="":"no earlier results", 1:"earlier results "_tEarlier)
	Quit tText_"."
}

/// The name of the analyte from the analyte table; the code when it is not listed.
ClassMethod AnalyteName(pCode As %String) As %String
{
	If ##class(Readback.Config.Analyte).CodeIdxExists(pCode, .tId) {
		Set tAnalyte = ##class(Readback.Config.Analyte).%OpenId(tId)
		Quit:$IsObject(tAnalyte) tAnalyte.Name
	}
	Quit pCode
}

/// The values and units of the earlier results of the same patient and analyte, newest first, as a short list.
ClassMethod EarlierSummary(pLab As Readback.Msg.LabResult) As %String
{
	Set tCollected = ##class(Readback.Triage.Context).CollectedOrNow(pLab)
	Set tH = $ZDateTimeH(tCollected, 3, , , , , , , , "")
	Quit:tH="" ""
	Set tFrom = $ZDateTime(($Piece(tH, ",", 1) - ##class(Readback.Triage.Context).#LookbackDays)_","_$Piece(tH, ",", 2), 3)
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_##class(Readback.Triage.Context).#MaxEarlier_" ValueText, Unit FROM Readback_Msg.LabResult WHERE PatientId = ? AND AnalyteCode = ? AND MessageControlId <> ? AND CollectedAt < ? AND CollectedAt >= ? ORDER BY CollectedAt DESC")
	Quit:$System.Status.IsError(tSC) ""
	Set tRS = tStmt.%Execute(pLab.PatientId, pLab.AnalyteCode, pLab.MessageControlId, tCollected, tFrom)
	If tRS.%SQLCODE < 0 { Quit "" }
	Set tList = ""
	While tRS.%Next() { Set tList = tList_$Select(tList="":"", 1:", ")_tRS.%Get("ValueText")_$Select(tRS.%Get("Unit")'="":" "_tRS.%Get("Unit"), 1:"") }
	Quit tList
}

}
