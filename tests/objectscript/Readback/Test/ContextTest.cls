/// The text sent to the agent, and the lookup of the patient's earlier stored results.
Class Readback.Test.ContextTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Msg.LabResult WHERE PatientId LIKE 'CTX%')
}

ClassMethod Save(pControlId As %String, pPatient As %String, pCode As %String, pValue As %String, pCollected As %String, pIndices As %String = "") As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pControlId, tLab.PatientId = pPatient, tLab.AnalyteCode = pCode
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = "g/dL", tLab.CollectedAt = pCollected
	Set tLab.ReferenceRange = "12.0-17.0", tLab.Source = "file", tLab.AgeYears = 56
	If pIndices '= "" { Do tLab.SampleIndices.Insert(pIndices) }
	Do tLab.%Save()
	Quit tLab
}

Method TestNoEarlierResults()
{
	Set tLab = ..Save("CTX-A-1", "CTX0000001", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText["No earlier results for this patient and analyte in the last 7 days.", "says explicitly that there are none")
	Do $$$AssertTrue(tText["Case id: CTX-A-1", "carries the case id")
	Do $$$AssertTrue(tText["Value: 8.1 g/dL (current-result)", "carries the value with unit")
	Do $$$AssertTrue(tText["Reference range: 12.0-17.0", "carries the reference range")
	Do $$$AssertTrue(tText["age 56 years", "carries the age")
	Do $$$AssertTrue(tText["Sample quality indices: none", "says there are no indices")
}

Method TestEarlierResultsNewestFirstMaxThree()
{
	Do ..Save("CTX-B-1", "CTX0000002", "718-7", 12.4, "2026-02-28 08:00:00")
	Do ..Save("CTX-B-2", "CTX0000002", "718-7", 12.0, "2026-02-27 08:00:00")
	Do ..Save("CTX-B-3", "CTX0000002", "718-7", 11.9, "2026-02-26 08:00:00")
	Do ..Save("CTX-B-4", "CTX0000002", "718-7", 11.8, "2026-02-25 08:00:00")
	Set tLab = ..Save("CTX-B-5", "CTX0000002", "718-7", 8.1, "2026-03-01 08:00:00", "HEMOLYSIS_INDEX=12")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText["1. 12.4 g/dL collected 2026-02-28 08:00:00 (earlier-result-1)", "the newest earlier result is first")
	Do $$$AssertTrue(tText["3. 11.9 g/dL", "the third is the third newest")
	Do $$$AssertTrue(tText'["11.8", "a fourth earlier result is not included")
	Do $$$AssertTrue(tText["Sample quality indices: HEMOLYSIS_INDEX=12", "sample indices are included")
}

Method TestOnlySameAnalyteSamePatientAndWithinSevenDays()
{
	Do ..Save("CTX-C-1", "CTX0000003", "718-7", 13.0, "2026-02-20 08:00:00")
	Do ..Save("CTX-C-2", "CTX0000003", "2823-3", 4.0, "2026-02-28 08:00:00")
	Do ..Save("CTX-C-3", "CTX0000009", "718-7", 14.0, "2026-02-28 08:00:00")
	Do ..Save("CTX-C-4", "CTX0000003", "718-7", 15.0, "2026-03-02 08:00:00")
	Set tLab = ..Save("CTX-C-5", "CTX0000003", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText["No earlier results", "older than 7 days, other analyte, other patient and later results are all left out")
}

Method TestTheResultItselfIsNeverIncluded()
{
	Set tLab = ..Save("CTX-D-1", "CTX0000004", "718-7", 8.1, "2026-03-01 08:00:00")
	Do ..Save("CTX-D-1", "CTX0000004", "718-7", 8.1, "2026-02-28 08:00:00")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText["No earlier results", "a stored result with the same control id is the result itself")
}

Method TestTextIsDeterministic()
{
	Do ..Save("CTX-E-1", "CTX0000005", "718-7", 12.4, "2026-02-28 08:00:00")
	Set tLab = ..Save("CTX-E-2", "CTX0000005", "718-7", 8.1, "2026-03-01 08:00:00")
	Do $$$AssertEquals(##class(Readback.Triage.Context).Build(tLab), ##class(Readback.Triage.Context).Build(tLab), "the same input gives the same text")
}

Method TestUnknownAge()
{
	Set tLab = ..Save("CTX-F-1", "CTX0000006", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tLab.AgeYears = ""
	Do $$$AssertTrue(##class(Readback.Triage.Context).Build(tLab)["age unknown", "an unknown age is stated")
}

}
