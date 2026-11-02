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
	Set tAssess = ..Assess(pOriginal.PatientId, pOriginal.AnalyteCode, pOriginal.MessageControlId, ##class(Readback.Triage.Context).CollectedOrNow(pOriginal), pOriginal.ValueNumeric, pOriginal.Unit, pEffective.ValueNumeric, pEffective.Unit)
	Quit:'tAssess.hit
	If tAssess.floorSeverity > pFloor.Severity {
		Set pFloor.Severity = tAssess.floorSeverity
		Set pFloor.RuleId = "delta:"_tAssess.analyteCode
	}
	Set pFloor.DeltaTriggered = 1
	Set pFloor.Note = $Extract($Select(pFloor.Note="":"", 1:pFloor.Note_"; ")_tAssess.note, 1, 300)
}

/// The change of a result against the same patient's earlier results of the same analyte, with the verdict of the
/// change rule, and no effect on anything. Apply uses it to raise the floor and the delta tool hands it to the agent
/// as information; the composition does not depend on what the agent does with it. Returns a %DynamicObject:
/// comparable (1 when a rule, a unit match and at least one earlier result in the window made a comparison possible),
/// hit (1 when the change is over the limit), verdict ("critical by change", "no critical change" or "not comparable"),
/// reason (why it is not comparable, else empty), analyteCode, unit, windowHours, limit, direction, change (the largest
/// move in the rule's direction, in the reference unit), floorSeverity and note (the text Apply adds to the floor).
ClassMethod Assess(pPatient As %String, pAnalyte As %String, pControlId As %String, pCollected As %String, pOriginalNumeric As %String, pOriginalUnit As %String, pEffectiveNumeric As %String, pEffectiveUnit As %String) As %DynamicObject
{
	Set tOut = {"comparable":0,"hit":0,"verdict":"not comparable","reason":"","analyteCode":(pAnalyte)}
	If pEffectiveNumeric = "" { Set tOut.reason = "the value is not numeric"  Quit tOut }
	If '##class(Readback.Config.DeltaRule).AnalyteIdxExists(pAnalyte, .tRuleId) { Set tOut.reason = "no change rule for this analyte"  Quit tOut }
	Set tRule = ##class(Readback.Config.DeltaRule).%OpenId(tRuleId)
	Set tOut.unit = tRule.Unit, tOut.windowHours = tRule.WindowHours, tOut.limit = tRule.MaxChange, tOut.direction = tRule.Direction
	If pEffectiveUnit '= tRule.Unit { Set tOut.reason = "no change rule for this unit"  Quit tOut }
	If (pOriginalNumeric = "") || (pOriginalNumeric = 0) { Set tOut.reason = "the value is not usable for a comparison"  Quit tOut }
	Set tFactor = pEffectiveNumeric / pOriginalNumeric
	Set tFrom = ..WindowStart(pCollected, tRule.WindowHours)
	If tFrom = "" { Set tOut.reason = "the collection time is not a timestamp"  Quit tOut }
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT ValueNumeric FROM Readback_Msg.LabResult WHERE PatientId = ? AND AnalyteCode = ? AND MessageControlId <> ? AND Unit = ? AND ValueNumeric IS NOT NULL AND CollectedAt < ? AND CollectedAt >= ?")
	If $System.Status.IsError(tSC) { Set tOut.reason = "the earlier results could not be read"  Quit tOut }
	Set tRS = tStmt.%Execute(pPatient, pAnalyte, pControlId, pOriginalUnit, pCollected, tFrom)
	Set tCompared = 0, tBest = "", tBestChange = ""
	While tRS.%Next() {
		Set tCompared = tCompared + 1
		Set tChange = (pOriginalNumeric - tRS.%Get("ValueNumeric")) * tFactor
		Set tMagnitude = $Case(tRule.Direction, "fall":-tChange, "rise":tChange, :$Select(tChange<0:-tChange, 1:tChange))
		If (tBest = "") || (tMagnitude > tBest) { Set tBest = tMagnitude, tBestChange = tChange }
	}
	If tCompared = 0 { Set tOut.reason = "no earlier result in the window in the same unit"  Quit tOut }
	Set tOut.comparable = 1
	Set tOut.change = +$Justify(tBestChange, 0, 4)
	Set tOut.floorSeverity = tRule.FloorSeverity
	If tBest > tRule.MaxChange {
		Set tOut.hit = 1, tOut.verdict = "critical by change"
		Set tOut.note = "critical by change: "_$Case(tRule.Direction, "fall":"fell", "rise":"rose", :"changed")_" by more than "_tRule.MaxChange_" "_tRule.Unit_" within "_tRule.WindowHours_" hours"
	} Else {
		Set tOut.verdict = "no critical change"
	}
	Quit tOut
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
