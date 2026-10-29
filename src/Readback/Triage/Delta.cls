/// The contextual floor: a change of the result from the patient's earlier results of the same analyte, inside a
/// window, raises the floor like a value limit does. It runs before the agent and is part of the floor, so the
/// agent can raise such a result and never lower it (P-1).
Class Readback.Triage.Delta
{

/// Raises pFloor when the result moved more than the rule of its analyte allows. pOriginal is the result as
/// received, pEffective the same result in the reference unit. Earlier results are compared in the unit of the
/// result as received (a mass concentration against a mass concentration), and the change is carried to the
/// reference unit with the factor the unit conversion itself produced, so there is no conversion table here.
/// An earlier result in another unit is not compared. No rule for the analyte, or nothing earlier in the
/// window, leaves the floor as it is.
ClassMethod Apply(pOriginal As Readback.Msg.LabResult, pEffective As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult)
{
	Quit:pEffective.ValueNumeric=""
	Quit:'##class(Readback.Config.DeltaRule).AnalyteIdxExists(pEffective.AnalyteCode, .tRuleId)
	Set tRule = ##class(Readback.Config.DeltaRule).%OpenId(tRuleId)
	Quit:pEffective.Unit'=tRule.Unit
	Quit:(pOriginal.ValueNumeric="")||(pOriginal.ValueNumeric=0)
	Set tFactor = pEffective.ValueNumeric / pOriginal.ValueNumeric
	Set tCollected = ##class(Readback.Triage.Context).CollectedOrNow(pOriginal)
	Set tFrom = ..WindowStart(tCollected, tRule.WindowHours)
	Quit:tFrom=""
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT ValueNumeric FROM Readback_Msg.LabResult WHERE PatientId = ? AND AnalyteCode = ? AND MessageControlId <> ? AND Unit = ? AND ValueNumeric IS NOT NULL AND CollectedAt < ? AND CollectedAt >= ?")
	Quit:$System.Status.IsError(tSC)
	Set tRS = tStmt.%Execute(pOriginal.PatientId, pOriginal.AnalyteCode, pOriginal.MessageControlId, pOriginal.Unit, tCollected, tFrom)
	Set tHit = 0
	While tRS.%Next() {
		Set tChange = (pOriginal.ValueNumeric - tRS.%Get("ValueNumeric")) * tFactor
		If $Case(tRule.Direction, "fall":-tChange, "rise":tChange, :$Select(tChange<0:-tChange, 1:tChange)) > tRule.MaxChange { Set tHit = 1  Quit }
	}
	Quit:'tHit
	Set tNote = "critical by change: "_$Case(tRule.Direction, "fall":"fell", "rise":"rose", :"changed")_" by more than "_tRule.MaxChange_" "_tRule.Unit_" within "_tRule.WindowHours_" hours"
	If tRule.FloorSeverity > pFloor.Severity {
		Set pFloor.Severity = tRule.FloorSeverity
		Set pFloor.RuleId = "delta:"_tRule.AnalyteCode
	}
	Set pFloor.DeltaTriggered = 1
	Set pFloor.Note = $Extract($Select(pFloor.Note="":"", 1:pFloor.Note_"; ")_tNote, 1, 300)
}

/// The timestamp pHours before pCollected, or empty when pCollected is not a timestamp.
ClassMethod WindowStart(pCollected As %String, pHours As %Integer) As %String
{
	Set tH = $ZDateTimeH(pCollected, 3, , , , , , , , "")
	Quit:tH="" ""
	Set tDay = $Piece(tH, ",", 1), tSec = $Piece(tH, ",", 2) - (pHours * 3600)
	While tSec < 0 { Set tSec = tSec + 86400, tDay = tDay - 1 }
	Quit $ZDateTime(tDay_","_tSec, 3)
}

}
