/// Deterministic severity floor from the critical range table. Runs before the agent.
Class Readback.Triage.Floor
{

/// Age group by whole years: neonate under 1, child 1 to 17, adult 18 and over. Unknown age uses adult.
ClassMethod AgeGroup(pAgeYears As %Integer) As %String
{
	Quit:pAgeYears="" "adult"
	Quit:pAgeYears<1 "neonate"
	Quit:pAgeYears<18 "child"
	Quit "adult"
}

ClassMethod IsCritical(pValue As %Numeric, pRangeId As %String) As %Boolean
{
	Set tRange = ##class(Readback.Config.Range).%OpenId(pRangeId)
	Quit:'$IsObject(tRange) 0
	Quit:(tRange.CriticalLow'="")&&(pValue<=tRange.CriticalLow) 1
	Quit:(tRange.CriticalHigh'="")&&(pValue>=tRange.CriticalHigh) 1
	Quit 0
}

/// Computes the floor of a stored lab result.
ClassMethod Compute(pLab As Readback.Msg.LabResult) As Readback.Triage.FloorResult
{
	Set tResult = ##class(Readback.Triage.FloorResult).%New()
	Set tNotes = ""
	If pLab.ValueNumeric = "" {
		Set tResult.Note = "value is not numeric, no rule applied"
		Quit tResult
	}
	Set tValue = pLab.ValueNumeric
	If pLab.AgeYears = "" { Set tNotes = "age unknown, adult range used" }
	Set tAge = ..AgeGroup(pLab.AgeYears)
	Set tCode = pLab.AnalyteCode, tUnit = pLab.Unit

	// Exact row: analyte, unit, age group. Fall back to the adult row when only that group is missing.
	Set tRowId = ""
	If ##class(Readback.Config.Range).RangeIdxExists(tCode, tUnit, tAge, .tRowId) {
	} ElseIf (tAge '= "adult") && ##class(Readback.Config.Range).RangeIdxExists(tCode, tUnit, "adult", .tRowId) {
		Set tNotes = tNotes_$Select(tNotes="":"", 1:"; ")_"no "_tAge_" range, adult range used"
	} Else {
		Set tRowId = ""
	}
	If tRowId '= "" {
		Set tRange = ##class(Readback.Config.Range).%OpenId(tRowId)
		Set tResult.RuleId = tRowId
		If ..IsCritical(tValue, tRowId) {
			Set tResult.Severity = tRange.FloorSeverity
		} Else {
			Set tNotes = tNotes_$Select(tNotes="":"", 1:"; ")_"within the critical limits"
		}
		Set tResult.Note = tNotes
		Quit tResult
	}

	// No row for this unit. Does the analyte exist at all?
	&sql(SELECT COUNT(*) INTO :tCount FROM Readback_Config.Range WHERE AnalyteCode = :tCode)
	If tCount = 0 {
		Set tResult.Note = $Select(tNotes="":"", 1:tNotes_"; ")_"no rule for analyte"
		Quit tResult
	}
	// Known analyte, unknown unit: do not guess, but never miss a value that is critical under any known unit.
	Set tResult.UnitUnknown = 1
	Set tCritical = 0
	Set tStmt = ##class(%SQL.Statement).%New()
	Do tStmt.%Prepare("SELECT ID, FloorSeverity FROM Readback_Config.Range WHERE AnalyteCode = ? AND AgeGroup = ?")
	Set tRS = tStmt.%Execute(tCode, tAge)
	While tRS.%Next() {
		If ..IsCritical(tValue, tRS.%Get("ID")) {
			Set tCritical = 1
			If tRS.%Get("FloorSeverity") > tResult.Severity { Set tResult.Severity = tRS.%Get("FloorSeverity"), tResult.RuleId = tRS.%Get("ID") }
		}
	}
	Set tResult.Note = $Select(tNotes="":"", 1:tNotes_"; ")_"unit not in rule table"_$Select(tCritical:"; value critical under another known unit", 1:"")
	Quit tResult
}

}
