/// The contextual floor: a change from the patient's earlier results raises the floor, before the agent, and the
/// agent can never lower it (P-1 extended to the change rule).
Class Readback.Test.DeltaTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Msg.LabResult WHERE PatientId LIKE 'DLT%')
}

ClassMethod Save(pControlId As %String, pPatient As %String, pCode As %String, pValue As %String, pUnit As %String, pCollected As %String) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pControlId, tLab.PatientId = pPatient, tLab.AnalyteCode = pCode
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.CollectedAt = pCollected, tLab.Source = "file", tLab.AgeYears = 56
	Do tLab.%Save()
	Quit tLab
}

/// The floor of a result whose own value is not critical, then the change rule on top of it.
ClassMethod Floor(pLab As Readback.Msg.LabResult, pEffective As Readback.Msg.LabResult = "") As Readback.Triage.FloorResult
{
	Set:'$IsObject(pEffective) pEffective = pLab
	Set tFloor = ##class(Readback.Triage.Floor).Compute(pEffective)
	Do ##class(Readback.Triage.Delta).Apply(pLab, pEffective, tFloor)
	Quit tFloor
}

Method TestAcuteHemoglobinDropRaisesTheFloor()
{
	Do ..Save("DLT-A-1", "DLT0000001", "718-7", 13.4, "g/dL", "2026-03-01 00:00:00")
	Set tFloor = ..Floor(..Save("DLT-A-2", "DLT0000001", "718-7", 9.8, "g/dL", "2026-03-01 12:00:00"))
	Do $$$AssertEquals(tFloor.Severity, 3, "a fall of 3.6 g/dL in 12 hours is critical by change although 9.8 is inside the limits")
	Do $$$AssertTrue(tFloor.DeltaTriggered, "the change rule is marked as triggered")
	Do $$$AssertEquals(tFloor.RuleId, "delta:718-7", "the rule id names the change rule")
	Do $$$AssertTrue(tFloor.Note["critical by change", "the note says why")
}

Method TestSmallOrSlowOrWrongDirectionDoesNotRaiseIt()
{
	Do ..Save("DLT-B-1", "DLT0000002", "718-7", 13.4, "g/dL", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-B-2", "DLT0000002", "718-7", 10.5, "g/dL", "2026-03-01 12:00:00")).Severity, 0, "a fall of 2.9 is not more than 3")
	Do ..Save("DLT-B-3", "DLT0000003", "718-7", 13.4, "g/dL", "2026-02-27 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-B-4", "DLT0000003", "718-7", 8.0, "g/dL", "2026-03-01 12:00:00")).Severity, 0, "an earlier result outside the 24 hours window does not count")
	Do ..Save("DLT-B-5", "DLT0000004", "718-7", 9.0, "g/dL", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-B-6", "DLT0000004", "718-7", 13.5, "g/dL", "2026-03-01 12:00:00")).Severity, 0, "a rise of hemoglobin is not the fall the rule describes")
	Do $$$AssertEquals(..Floor(..Save("DLT-B-7", "DLT0000005", "718-7", 9.0, "g/dL", "2026-03-01 12:00:00")).Severity, 0, "no earlier result, no change rule")
}

Method TestPotassiumChangeInEitherDirection()
{
	Do ..Save("DLT-C-1", "DLT0000006", "2823-3", 4.3, "mmol/L", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-C-2", "DLT0000006", "2823-3", 6.1, "mmol/L", "2026-03-01 12:00:00")).Severity, 3, "potassium up 1.8 in 12 hours, value below the limit, is critical by change")
	Do ..Save("DLT-C-3", "DLT0000007", "2823-3", 5.9, "mmol/L", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-C-4", "DLT0000007", "2823-3", 4.0, "mmol/L", "2026-03-01 12:00:00")).Severity, 3, "a fall of 1.9 counts as well")
	Do ..Save("DLT-C-5", "DLT0000008", "2823-3", 5.8, "mmol/L", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-C-6", "DLT0000008", "2823-3", 6.4, "mmol/L", "2026-03-01 12:00:00")).Severity, 0, "a rise of 0.6 is not more than 1.5")
}

Method TestAnotherPatientOrAnalyteIsNotCompared()
{
	Do ..Save("DLT-D-1", "DLT0000009", "718-7", 13.4, "g/dL", "2026-03-01 00:00:00")
	Do ..Save("DLT-D-2", "DLT0000010", "2823-3", 4.0, "mmol/L", "2026-03-01 00:00:00")
	Do $$$AssertEquals(..Floor(..Save("DLT-D-3", "DLT0000011", "718-7", 8.0, "g/dL", "2026-03-01 12:00:00")).Severity, 0, "another patient")
	Do $$$AssertEquals(..Floor(..Save("DLT-D-4", "DLT0000009", "2823-3", 6.0, "mmol/L", "2026-03-01 12:00:00")).Severity, 0, "another analyte of the same patient")
}

Method TestGlucoseChangeIsCarriedToTheReferenceUnit()
{
	// Received in mg/dL, rule in mmol/L: the factor is the one the conversion produced (here 1 mg/dL = 1/18.0156 mmol/L).
	Do ..Save("DLT-E-1", "DLT0000012", "2345-7", 90, "mg/dL", "2026-03-01 00:00:00")
	Set tNow = ..Save("DLT-E-2", "DLT0000012", "2345-7", 400, "mg/dL", "2026-03-01 12:00:00")
	Set tEffective = tNow.%ConstructClone()
	Set tEffective.ValueNumeric = 400 / 18.0156, tEffective.Unit = "mmol/L"
	Set tFloor = ..Floor(tNow, tEffective)
	Do $$$AssertEquals(tFloor.Severity, 3, "a rise of 310 mg/dL (17.2 mmol/L) is more than 11.1 mmol/L")
	Do ..Save("DLT-E-3", "DLT0000013", "2345-7", 90, "mg/dL", "2026-03-01 00:00:00")
	Set tSmall = ..Save("DLT-E-4", "DLT0000013", "2345-7", 200, "mg/dL", "2026-03-01 12:00:00")
	Set tSmallEffective = tSmall.%ConstructClone()
	Set tSmallEffective.ValueNumeric = 200 / 18.0156, tSmallEffective.Unit = "mmol/L"
	Do $$$AssertEquals(..Floor(tSmall, tSmallEffective).Severity, 0, "a rise of 110 mg/dL (6.1 mmol/L) is less than 11.1 mmol/L")
}

Method TestAnEarlierResultInAnotherUnitIsNotCompared()
{
	Do ..Save("DLT-F-1", "DLT0000014", "2345-7", 5, "mmol/L", "2026-03-01 00:00:00")
	Set tNow = ..Save("DLT-F-2", "DLT0000014", "2345-7", 400, "mg/dL", "2026-03-01 12:00:00")
	Set tEffective = tNow.%ConstructClone()
	Set tEffective.ValueNumeric = 400 / 18.0156, tEffective.Unit = "mmol/L"
	Do $$$AssertEquals(..Floor(tNow, tEffective).Severity, 0, "no conversion of the earlier result is invented, so it is not compared")
}

Method TestAnUnconvertedUnitGetsNoChangeRule()
{
	Do ..Save("DLT-G-1", "DLT0000015", "2345-7", 90, "mg/dL", "2026-03-01 00:00:00")
	Set tNow = ..Save("DLT-G-2", "DLT0000015", "2345-7", 400, "mg/dL", "2026-03-01 12:00:00")
	Do $$$AssertEquals(..Floor(tNow).DeltaTriggered, 0, "the result is still in mg/dL, the rule is in mmol/L: not applied")
}

Method TestTheAgentCannotLowerACriticalByChange()
{
	Do ..Save("DLT-H-1", "DLT0000016", "718-7", 13.4, "g/dL", "2026-03-01 00:00:00")
	Set tFloor = ..Floor(..Save("DLT-H-2", "DLT0000016", "718-7", 9.8, "g/dL", "2026-03-01 12:00:00"))
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = 1, tAgent.Decision = "NON_CRITICAL", tAgent.Severity = 0, tAgent.Confidence = "high"
	Set tFinal = ##class(Readback.Triage.Composer).Compose(tFloor, tAgent)
	Do $$$AssertEquals(tFinal.FinalSeverity, 3, "the agent says non-critical and the final severity is still 3")
	Do $$$AssertEquals(tFinal.Route, "readback", "the route is read-back")
	Set tFailed = ##class(Readback.Triage.AgentOutput).%New()
	Set tFailed.Valid = 0, tFailed.FailureKind = "timeout", tFailed.FailureReason = "no answer"
	Do $$$AssertEquals(##class(Readback.Triage.Composer).Compose(tFloor, tFailed).Route, "readback", "with no agent answer at all it is still read-back")
	Do $$$AssertEquals(##class(Readback.Triage.Composer).Compose(tFloor, "").Route, "readback", "and with no agent at all (budget reached)")
}

Method TestTheChangeRuleTableIsValidated()
{
	Set tDir = ##class(%File).TempFilename("json")
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tDir)
	Do tStream.Write("{""rules"":[{""analyteCode"":""718-7"",""unit"":""mg/dL"",""maxChange"":3,""windowHours"":24,""direction"":""fall"",""floorSeverity"":3,""source"":""x""}]}")
	Do tStream.%Save()
	Set tSC = ##class(Readback.Config.Loader).LoadDeltaRules(tDir, .tN)
	Do $$$AssertTrue($$$ISERR(tSC)&&($System.Status.GetErrorText(tSC)["reference unit"), "a rule in another unit than the reference unit of the analyte is refused")
	Do ##class(%File).Delete(tDir)
	Do ##class(Readback.Config.Loader).LoadAll()
}

}
