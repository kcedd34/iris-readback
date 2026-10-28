/// The text used to search and to store cases carries no identifier of a person or a message.
Class Readback.Test.DescribeTest Extends %UnitTest.TestCase
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
	&sql(DELETE FROM Readback_Msg.LabResult WHERE PatientId = 'SYN7777123')
}

ClassMethod Save(pControl As %String, pValue As %String, pUnit As %String, pCollected As %String) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pControl, tLab.PatientId = "SYN7777123", tLab.AnalyteCode = "2823-3"
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.CollectedAt = pCollected, tLab.AgeYears = 56
	Set tLab.RawHL7 = "MSH|^~\&|PID|1||SYN7777123^^^SYN^MR||ZZNAME^ZZFIRST||19670101|F|NTE|dialysis patient Zed"
	Set tLab.BirthDate = $ZDateH("1967-01-01", 3)
	Do tLab.%Save()
	Quit tLab
}

Method TestTextHasTheClinicalContent()
{
	Set tLab = ..Save("DSC-MSG-A1", "6.9", "mmol/L", "2026-03-01 08:00:00")
	Do tLab.SampleIndices.Insert("hemolysis 250")
	Set tText = ##class(Readback.Retrieval.Describe).Text(tLab)
	Do $$$AssertTrue(tText["Potassium", "the analyte name is there: "_tText)
	Do $$$AssertTrue(tText["6.9 mmol/L", "the value and unit")
	Do $$$AssertTrue(tText["adult", "the age group")
	Do $$$AssertTrue(tText["hemolysis 250", "the sample indices")
	Do $$$AssertTrue(tText["no earlier results", "and the earlier-result summary says there are none")
}

Method TestNoSampleProblemWording()
{
	Set tLab = ..Save("DSC-MSG-A2", "4.0", "mmol/L", "2026-03-02 08:00:00")
	Do $$$AssertTrue(##class(Readback.Retrieval.Describe).Text(tLab)["no sample quality problem", "no indices gives the fixed wording")
}

Method TestEarlierResultsAreSummarizedByValue()
{
	Do ..Save("DSC-MSG-B1", "5.0", "mmol/L", "2026-03-03 06:00:00")
	Do ..Save("DSC-MSG-B2", "5.4", "mmol/L", "2026-03-03 07:00:00")
	Set tLab = ..Save("DSC-MSG-B3", "6.9", "mmol/L", "2026-03-03 08:00:00")
	Set tText = ##class(Readback.Retrieval.Describe).Text(tLab)
	Do $$$AssertTrue(tText["earlier results 5.4 mmol/L, 5 mmol/L" || (tText["earlier results 5.4 mmol/L, 5.0 mmol/L"), "the earlier values, newest first: "_tText)
}

Method TestNoIdentifierEverReachesTheText()
{
	Set tLab = ..Save("DSC-MSG-C1", "6.9", "mmol/L", "2026-03-04 09:00:00")
	Do ..Save("DSC-MSG-C0", "5.1", "mmol/L", "2026-03-04 07:00:00")
	Do tLab.SampleIndices.Insert("hemolysis 250")
	Set tText = ##class(Readback.Retrieval.Describe).Text(tLab)
	For tSecret = "SYN7777123", "DSC-MSG-C1", "DSC-MSG-C0", "ZZNAME", "ZZFIRST", "1967", "19670101", "Zed", "dialysis patient", "MSH", "PID" {
		Do $$$AssertTrue(tText'[tSecret, "the text does not contain '"_tSecret_"'")
	}
}

Method TestDeterministic()
{
	Set tLab = ..Save("DSC-MSG-D1", "6.9", "mmol/L", "2026-03-05 09:00:00")
	Do $$$AssertEquals(##class(Readback.Retrieval.Describe).Text(tLab), ##class(Readback.Retrieval.Describe).Text(tLab), "same input, same text")
}

}
