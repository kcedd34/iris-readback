/// The case binding: facts published by the process, copied by the operation, readable by the tools, gone after Clear.
Class Readback.Test.BindingTest Extends %UnitTest.TestCase
{

ClassMethod Lab(pId As %String, pPatient As %String, pValue As %String, pUnit As %String) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pId, tLab.PatientId = pPatient, tLab.AnalyteCode = "2823-3"
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.CollectedAt = "2026-03-01 08:00:00"
	Do tLab.SampleIndices.Insert("HEMOLYSIS_INDEX=120")
	Quit tLab
}

Method TestPublishBindReadClear()
{
	Set tLab = ..Lab("BT-1", "SYN1", "6.9", "mmol/L")
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = 3, tFloor.RuleId = "range:2823-3", tFloor.Note = "above the critical limit"
	Do ##class(Readback.Tools.Binding).Publish(tLab, tLab, tFloor)
	Do $$$AssertStatusOK(##class(Readback.Tools.Binding).Bind("BT-1"), "a published case binds")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).IsBound(), 1, "bound")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Get("patientId"), "SYN1", "the patient comes from the server")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Get("floorSeverity"), 3, "the floor is carried")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Indices().%Get(0), "HEMOLYSIS_INDEX=120", "the indices are carried")
	Do ##class(Readback.Tools.Binding).Clear()
	Do $$$AssertEquals(##class(Readback.Tools.Binding).IsBound(), 0, "cleared")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Get("patientId"), "", "nothing is left after Clear")
	Do ##class(Readback.Tools.Binding).Unpublish("BT-1")
}

Method TestSecondBindReplaces()
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Do ##class(Readback.Tools.Binding).Publish(..Lab("BT-2", "SYN2", "4.0", "mmol/L"), ..Lab("BT-2", "SYN2", "4.0", "mmol/L"), tFloor)
	Do ##class(Readback.Tools.Binding).Publish(..Lab("BT-3", "SYN3", "4.1", "mmol/L"), ..Lab("BT-3", "SYN3", "4.1", "mmol/L"), tFloor)
	Do ##class(Readback.Tools.Binding).Bind("BT-2")
	Do ##class(Readback.Tools.Binding).Bind("BT-3")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Get("patientId"), "SYN3", "the second case replaced the first")
	Do ##class(Readback.Tools.Binding).Clear()
	Do ##class(Readback.Tools.Binding).Unpublish("BT-2")
	Do ##class(Readback.Tools.Binding).Unpublish("BT-3")
}

Method TestUnknownCaseFailsClosed()
{
	Do $$$AssertStatusNotOK(##class(Readback.Tools.Binding).Bind("NO-SUCH-CASE"), "nothing was published for it")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).IsBound(), 0, "and nothing is bound")
	Do $$$AssertStatusNotOK(##class(Readback.Tools.Binding).Bind(""), "an empty case id fails")
	Do $$$AssertEquals(##class(Readback.Tools.Binding).Get("patientId"), "", "no binding means no patient")
}

}
