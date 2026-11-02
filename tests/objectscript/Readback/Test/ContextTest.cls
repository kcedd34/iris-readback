/// The text sent to the agent (the case and its value, nothing more) and the lookup of the patient's earlier stored
/// results that the history tool uses.
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

Method TestTheTextIsTheCaseAndItsValue()
{
	Set tLab = ..Save("CTX-A-1", "CTX0000001", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText["Case id: CTX-A-1", "carries the case id")
	Do $$$AssertTrue(tText["Value: 8.1 g/dL (current-result)", "carries the value with unit")
	Do $$$AssertTrue(tText["Reference range: 12.0-17.0", "carries the reference range")
	Do $$$AssertTrue(tText["Patient age: 56 years", "carries the age")
	Do $$$AssertTrue(tText["Collected at: 2026-03-01 08:00:00", "carries the collection time")
	Do $$$AssertTrue(tText["Analyte code: 718-7", "carries the analyte")
}

Method TestTheTextHoldsNothingTheToolsProvide()
{
	Do ..Save("CTX-B-1", "CTX0000002", "718-7", 12.4, "2026-02-28 08:00:00")
	Set tLab = ..Save("CTX-B-0", "CTX0000002", "718-7", 8.1, "2026-03-01 08:00:00", "HEMOLYSIS_INDEX=120")
	Set tText = ##class(Readback.Triage.Context).Build(tLab)
	Do $$$AssertTrue(tText'["12.4", "the earlier results come through the history tool, not the text")
	Do $$$AssertTrue(tText'["HEMOLYSIS", "the sample quality comes through its tool, not the text")
	Do $$$AssertTrue(tText'["Policy passages", "the policy comes through its tool, not the text")
	Do $$$AssertTrue(tText'["CTX0000002", "no patient identifier is in the text: no tool takes one")
}

Method TestUnknownAgeAndConversion()
{
	Set tLab = ..Save("CTX-C-1", "CTX0000003", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tLab.AgeYears = ""
	Do $$$AssertTrue(##class(Readback.Triage.Context).Build(tLab)["Patient age: unknown", "an unknown age is stated")
	Do $$$AssertTrue(##class(Readback.Triage.Context).Build(tLab, {"outcome":"converted","value":"10.0","unit":"mmol/L"})["Converted value: 10.0 mmol/L (reference unit of the analyte)", "a conversion is stated")
	Do $$$AssertTrue(##class(Readback.Triage.Context).Build(tLab, {"outcome":"not-convertible"})["unit not convertible", "an unconvertible unit is stated")
	Do $$$AssertTrue(##class(Readback.Triage.Context).Build(tLab, {"outcome":"unavailable"})["unit conversion unavailable", "an unavailable conversion is stated")
}

Method TestTextIsDeterministic()
{
	Set tLab = ..Save("CTX-D-1", "CTX0000004", "718-7", 8.1, "2026-03-01 08:00:00")
	Do $$$AssertEquals(##class(Readback.Triage.Context).Build(tLab), ##class(Readback.Triage.Context).Build(tLab), "the same input gives the same text")
}

Method TestEarlierRowsNewestFirstMaxThree()
{
	Do ..Save("CTX-E-1", "CTX0000005", "718-7", 12.4, "2026-02-28 08:00:00")
	Do ..Save("CTX-E-2", "CTX0000005", "718-7", 12.0, "2026-02-27 08:00:00")
	Do ..Save("CTX-E-3", "CTX0000005", "718-7", 11.9, "2026-02-26 08:00:00")
	Do ..Save("CTX-E-4", "CTX0000005", "718-7", 11.8, "2026-02-25 08:00:00")
	Set tRows = ##class(Readback.Triage.Context).EarlierRows("CTX0000005", "718-7", "CTX-E-0", "2026-03-01 08:00:00")
	Do $$$AssertEquals(tRows.%Size(), 3, "at most three")
	Do $$$AssertEquals(tRows.%Get(0).value, "12.4", "newest first")
	Do $$$AssertEquals(tRows.%Get(2).value, "11.9", "the third is the third newest")
	Do $$$AssertEquals(tRows.%Get(0).id, "earlier-result-1", "with an identifier to cite")
	Do $$$AssertEquals(##class(Readback.Triage.Context).EarlierRows("CTX0000005", "718-7", "CTX-E-0", "2026-03-01 08:00:00", 1).%Size(), 1, "a smaller limit is honored")
}

Method TestEarlierRowsKeepsToTheWindowPatientAndAnalyte()
{
	Do ..Save("CTX-F-1", "CTX0000006", "718-7", 12.4, "2026-02-28 08:00:00")
	Do ..Save("CTX-F-OLD", "CTX0000006", "718-7", 13.0, "2026-02-10 08:00:00")
	Do ..Save("CTX-F-OTHER", "CTX0000006", "2823-3", 4.0, "2026-02-28 09:00:00")
	Do ..Save("CTX-F-PAT", "CTX0000007", "718-7", 12.9, "2026-02-28 08:00:00")
	Do ..Save("CTX-F-LATER", "CTX0000006", "718-7", 7.0, "2026-03-02 08:00:00")
	Set tRows = ##class(Readback.Triage.Context).EarlierRows("CTX0000006", "718-7", "CTX-F-0", "2026-03-01 08:00:00")
	Do $$$AssertEquals(tRows.%Size(), 1, "older than 7 days, other analyte, other patient and later results are all left out")
	Do $$$AssertEquals(tRows.%Get(0).value, "12.4", "only the one inside the window")
}

Method TestTheResultItselfIsNeverAnEarlierResult()
{
	Do ..Save("CTX-G-1", "CTX0000008", "718-7", 12.4, "2026-02-28 08:00:00")
	Set tLab = ..Save("CTX-G-0", "CTX0000008", "718-7", 8.1, "2026-03-01 08:00:00")
	Set tRows = ##class(Readback.Triage.Context).EarlierRows("CTX0000008", "718-7", "CTX-G-0", "2026-03-01 08:00:00")
	Do $$$AssertEquals(tRows.%Size(), 1, "the result itself is not an earlier result")
}

}
