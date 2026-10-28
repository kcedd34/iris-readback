/// The deterministic severity floor, against the shipped demonstration range table.
Class Readback.Test.FloorTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Lab(pCode As %String, pUnit As %String, pValue As %String, pAge As %Integer = 40) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.AnalyteCode = pCode, tLab.Unit = pUnit, tLab.ValueText = pValue, tLab.AgeYears = pAge
	Set:$IsValidNum(pValue) tLab.ValueNumeric = pValue
	Quit tLab
}

Method TestAdultPotassium()
{
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 6.9)).Severity, 3, "potassium 6.9 is critical for an adult")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 6.4)).Severity, 0, "potassium 6.4 is below the high limit")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 5.0)).Severity, 0, "a normal value has floor 0")
}

Method TestLimitsAreInclusive()
{
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 6.5)).Severity, 3, "exactly the high limit is critical")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 2.5)).Severity, 3, "exactly the low limit is critical")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 2.6)).Severity, 0, "just above the low limit is not critical")
}

Method TestOtherAnalytes()
{
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("718-7", "g/dL", 6.8)).Severity, 3, "hemoglobin 6.8 is critical")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("718-7", "g/dL", 8.1)).Severity, 0, "hemoglobin 8.1 is inside the limit, the agent decides")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mmol/L", 30)).Severity, 3, "glucose 30 mmol/L is critical")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mmol/L", 5)).Severity, 0, "glucose 5 mmol/L is not critical")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mmol/L", 2.2)).Severity, 3, "glucose 2.2 mmol/L is at the low limit")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2951-2", "mmol/L", 118)).Severity, 3, "sodium 118 is critical")
}

Method TestAgeGroups()
{
	Do $$$AssertEquals(##class(Readback.Triage.Floor).AgeGroup(0), "neonate", "under one year is neonate")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).AgeGroup(1), "child", "one year is child")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).AgeGroup(17), "child", "seventeen is child")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).AgeGroup(18), "adult", "eighteen is adult")
	Set tSC = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Readback_Config.Range SET CriticalHigh = 5.0 WHERE AnalyteCode = '2823-3' AND AgeGroup = 'child'")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 5.5, 10)).Severity, 3, "a child uses the child row")
	Do $$$AssertEquals(##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", 5.5, 40)).Severity, 0, "an adult keeps the adult row")
	Do ##class(Readback.Config.Loader).LoadAll()
}

Method TestUnknownAgeUsesAdult()
{
	Set tLab = ..Lab("2823-3", "mmol/L", 6.9, "")
	Set tFloor = ##class(Readback.Triage.Floor).Compute(tLab)
	Do $$$AssertEquals(tFloor.Severity, 3, "still evaluated")
	Do $$$AssertTrue(tFloor.Note["age unknown, adult range used", "the note records the assumption")
}

Method TestUnknownAnalyte()
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("9999-9", "mmol/L", 99))
	Do $$$AssertEquals(tFloor.Severity, 0, "no rule gives the lowest severity")
	Do $$$AssertTrue(tFloor.Note["no rule for analyte", "the note says no rule applied")
	Do $$$AssertEquals(tFloor.UnitUnknown, 0, "an unknown analyte is not a unit problem")
}

Method TestNonNumericValue()
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mmol/L", "HEMOLYZED"))
	Do $$$AssertEquals(tFloor.Severity, 0, "a non-numeric value gets floor 0")
	Do $$$AssertTrue(tFloor.Note["not numeric", "the note says why")
}

Method TestUnitNotInTable()
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mEq/L", 4.2))
	Do $$$AssertEquals(tFloor.Severity, 0, "an unknown unit with an unremarkable value gets floor 0")
	Do $$$AssertEquals(tFloor.UnitUnknown, 1, "the unit is flagged for review")
	Do $$$AssertTrue(tFloor.Note["unit not in rule table", "the note uses the fixed reason")
}

Method TestUnknownUnitButCriticalUnderAKnownUnit()
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "mEq/L", 6.9))
	Do $$$AssertEquals(tFloor.Severity, 3, "conservative: critical under a known unit stays critical")
	Do $$$AssertEquals(tFloor.UnitUnknown, 1, "and the unit is still flagged")
}

Method TestUnitIsCaseSensitive()
{
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2823-3", "MMOL/L", 4.2))
	Do $$$AssertEquals(tFloor.UnitUnknown, 1, "a unit that differs in case is not the table unit")
}

Method TestGlucoseInMgPerDlIsAnUnknownUnitHereAndStaysConservative()
{
	// The conversion to mmol/L happens before the floor (feature 3); if it did not, a raw mg/dL value is
	// judged conservatively: critical under any known unit stays critical.
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mg/dL", 520))
	Do $$$AssertEquals(tFloor.UnitUnknown, 1, "mg/dL is not a table unit for glucose any more")
	Do $$$AssertEquals(tFloor.Severity, 3, "520 is critical under the table unit, so it stays critical")
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mg/dL", 2.0))
	Do $$$AssertEquals(tFloor.Severity, 3, "2.0 is below the low limit of the table unit, so it stays critical too")
	Set tFloor = ##class(Readback.Triage.Floor).Compute(..Lab("2345-7", "mg/dL", 10))
	Do $$$AssertEquals(tFloor.Severity, 0, "10 is inside the limits of the table unit, so it is not critical by this path")
	Do $$$AssertEquals(tFloor.UnitUnknown, 1, "and the unit is still flagged for review")
}

}
