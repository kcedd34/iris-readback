/// The four tools: their contracts, their empty cases, that each is bounded and that none writes anything.
Class Readback.Test.ToolsTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Do ##class(Readback.Tools.Binding).Clear()
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Msg.LabResult WHERE PatientId LIKE 'TLS%')
}

ClassMethod Save(pControlId As %String, pPatient As %String, pCode As %String, pValue As %String, pUnit As %String, pCollected As %String, pIndex As %String = "") As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pControlId, tLab.PatientId = pPatient, tLab.AnalyteCode = pCode
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.CollectedAt = pCollected, tLab.Source = "file", tLab.AgeYears = 56
	If pIndex '= "" { Do tLab.SampleIndices.Insert(pIndex) }
	Do tLab.%Save()
	Quit tLab
}

/// Binds a case as the operation would.
Method Bind(pLab As Readback.Msg.LabResult, pFloorSeverity As %Integer = 0)
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pFloorSeverity
	Do ##class(Readback.Tools.Binding).Publish(pLab, pLab, tFloor)
	Do $$$AssertStatusOK(##class(Readback.Tools.Binding).Bind(pLab.MessageControlId), "the case binds")
}

Method TestHistoryReturnsTheWindowAndCeiling()
{
	Do ..Save("TLS-H-1", "TLS0000001", "718-7", 12.4, "g/dL", "2026-02-28 08:00:00")
	Do ..Save("TLS-H-2", "TLS0000001", "718-7", 12.0, "g/dL", "2026-02-27 08:00:00")
	Do ..Save("TLS-H-3", "TLS0000001", "718-7", 11.9, "g/dL", "2026-02-26 08:00:00")
	Do ..Save("TLS-H-4", "TLS0000001", "718-7", 11.8, "g/dL", "2026-02-25 08:00:00")
	Do ..Save("TLS-H-OLD", "TLS0000001", "718-7", 13.0, "g/dL", "2026-02-10 08:00:00")
	Set tLab = ..Save("TLS-H-0", "TLS0000001", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).PatientHistory())
	Do $$$AssertEquals(tOut.found, 3, "at most three, the ceiling of feature 2")
	Do $$$AssertEquals(tOut.earlier.%Get(0).value, "12.4", "newest first")
	Do $$$AssertEquals(tOut.earlier.%Get(0).id, "earlier-result-1", "with an identifier to cite")
	Set tTwo = {}.%FromJSON(##class(Readback.Tools.Impl).PatientHistory(2))
	Do $$$AssertEquals(tTwo.found, 2, "a smaller limit is honored")
	Set tBig = {}.%FromJSON(##class(Readback.Tools.Impl).PatientHistory(50))
	Do $$$AssertEquals(tBig.found, 3, "a larger limit never passes the ceiling")
	Do $$$AssertTrue(tOut.earlier.%ToJSON()'["TLS-H-0", "never the result itself")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestHistoryWithNothingSaysSo()
{
	Set tLab = ..Save("TLS-N-0", "TLS0000002", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).PatientHistory())
	Do $$$AssertEquals(tOut.found, 0, "none found")
	Do $$$AssertTrue(tOut.note["no earlier results", "and it says so")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestHistoryNeverReachesAnotherPatient()
{
	Do ..Save("TLS-X-1", "TLS0000003", "718-7", 12.4, "g/dL", "2026-02-28 08:00:00")
	Set tLab = ..Save("TLS-X-0", "TLS0000004", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).PatientHistory())
	Do $$$AssertEquals(tOut.found, 0, "another patient's results are not reachable")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestDeltaVerdictEqualsTheRule()
{
	Do ..Save("TLS-D-1", "TLS0000005", "718-7", 12.4, "g/dL", "2026-02-28 20:00:00")
	Set tLab = ..Save("TLS-D-0", "TLS0000005", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).DeltaAssessment())
	Do $$$AssertEquals(tOut.id, "delta-assessment", "with an identifier to cite")
	Do $$$AssertEquals(tOut.comparable, 1, "comparable")
	Do $$$AssertEquals(tOut.floorVerdict, "critical by change", "the verdict is the rule's")
	Do $$$AssertEquals(tOut.change, -4.3, "the change is in the reference unit")
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Do ##class(Readback.Triage.Delta).Apply(tLab, tLab, tFloor)
	Do $$$AssertEquals(tFloor.DeltaTriggered, 1, "and the rule raises the floor for the same case")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestDeltaNotComparableIsNeverInvented()
{
	Set tLab = ..Save("TLS-ND-0", "TLS0000006", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).DeltaAssessment())
	Do $$$AssertEquals(tOut.comparable, 0, "no earlier result: not comparable")
	Do $$$AssertEquals(tOut.floorVerdict, "not comparable", "the verdict says so")
	Do $$$AssertTrue(tOut.reason'="", "with a reason")
	Do $$$AssertTrue('tOut.%IsDefined("change"), "and no change is invented")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestDeltaAnotherUnitIsNotCompared()
{
	Do ..Save("TLS-U-1", "TLS0000007", "718-7", 124, "g/L", "2026-02-28 20:00:00")
	Set tLab = ..Save("TLS-U-0", "TLS0000007", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).DeltaAssessment())
	Do $$$AssertEquals(tOut.comparable, 0, "an earlier result in another unit is not compared")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestSampleQualityListsIndices()
{
	Set tLab = ..Save("TLS-S-0", "TLS0000008", "2823-3", 6.9, "mmol/L", "2026-03-01 08:00:00", "HEMOLYSIS_INDEX=120")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).SampleQuality())
	Do $$$AssertEquals(tOut.indices.%Get(0).id, "sample-index-hemolysis", "an identifier to cite")
	Do $$$AssertEquals(tOut.indices.%Get(0).value, "120", "the value")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestSampleQualityWithNoneSaysSo()
{
	Set tLab = ..Save("TLS-S-1", "TLS0000009", "2823-3", 4.0, "mmol/L", "2026-03-01 08:00:00")
	Do ..Bind(tLab)
	Set tOut = {}.%FromJSON(##class(Readback.Tools.Impl).SampleQuality())
	Do $$$AssertEquals(tOut.indices.%Size(), 0, "no indices")
	Do $$$AssertTrue(tOut.note["no sample quality", "and it says so")
	Do ##class(Readback.Tools.Binding).Clear()
}

Method TestNoToolRunsWithoutACase()
{
	Do ##class(Readback.Tools.Binding).Clear()
	For tMethod = "PatientHistory", "DeltaAssessment", "SampleQuality" {
		Set tRaised = 0
		Try { Do $ClassMethod("Readback.Tools.Impl", tMethod) } Catch ex { Set tRaised = 1 }
		Do $$$AssertEquals(tRaised, 1, tMethod_" refuses to run with no bound case")
	}
}

Method TestNoToolWritesAnything()
{
	Set tLab = ..Save("TLS-W-0", "TLS0000010", "718-7", 8.1, "g/dL", "2026-03-01 08:00:00", "HEMOLYSIS_INDEX=10")
	Do ..Bind(tLab)
	Set tBefore = ..Counts()
	Do ##class(Readback.Tools.Impl).PatientHistory()
	Do ##class(Readback.Tools.Impl).DeltaAssessment()
	Do ##class(Readback.Tools.Impl).SampleQuality()
	Do $$$AssertEquals(..Counts(), tBefore, "no stored result, decision, task or recording changed")
	Do ##class(Readback.Tools.Binding).Clear()
}

ClassMethod Counts() As %String
{
	&sql(SELECT COUNT(*) INTO :a FROM Readback_Msg.LabResult)
	&sql(SELECT COUNT(*) INTO :b FROM Readback_Trace.Decision)
	&sql(SELECT COUNT(*) INTO :c FROM Readback_Replay.Recording)
	&sql(SELECT COUNT(*) INTO :d FROM Readback_Config.Budget)
	Quit a_"/"_b_"/"_c_"/"_d
}

Method TestResultsAreBounded()
{
	Set tObj = {"found":9,"earlier":[]}
	For i = 1:1:40 { Do tObj.earlier.%Push({"id":("earlier-result-"_i),"value":"123456789012345678901234567890","unit":"g/dL","collectedAt":"2026-02-28 08:00:00"}) }
	Set tText = ##class(Readback.Tools.Impl).Bounded(tObj)
	Do $$$AssertTrue($Length(tText) '> ##class(Readback.Config.AgentTools).Current().ToolResultMaxChars, "within the configured size")
	Set tBack = {}.%FromJSON(tText)
	Do $$$AssertEquals(tBack.truncated, 1, "and it says it was cut")
}

}
