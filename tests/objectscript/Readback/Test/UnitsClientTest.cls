/// The pure helpers around the unit conversion component. The component itself is checked by
/// tests/java/run_java_tests.sh and the whole path by tests/e2e/units_check.py.
Class Readback.Test.UnitsClientTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Lab(pCode As %String, pValue As %String, pUnit As %String) As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.AnalyteCode = pCode, tLab.ValueText = pValue, tLab.Unit = pUnit
	Set:$IsValidNum(pValue) tLab.ValueNumeric = pValue
	Quit tLab
}

ClassMethod Answer(pOutcome As %String, pValue As %String = "", pUnit As %String = "", pMessage As %String = "") As EnsLib.PEX.Message
{
	Set tMsg = ##class(EnsLib.PEX.Message).%New("com.readback.units.ConvertResponse")
	Set tMsg.outcome = pOutcome, tMsg.value = pValue, tMsg.unit = pUnit, tMsg.message = pMessage
	Quit tMsg
}

Method TestNeedsConversion()
{
	Do $$$AssertEquals(##class(Readback.Units.Client).NeedsConversion(..Lab("2345-7", "540", "mg/dL"), .tA), "convert", "a different unit needs conversion")
	Do $$$AssertEquals(tA.ReferenceUnit, "mmol/L", "the analyte is returned")
	Do $$$AssertEquals(##class(Readback.Units.Client).NeedsConversion(..Lab("2345-7", "30", "mmol/L"), .tA), "not-needed", "the reference unit needs none")
	Do $$$AssertEquals(##class(Readback.Units.Client).NeedsConversion(..Lab("2345-7", "30", " mmol/L "), .tA), "not-needed", "spaces around the unit do not matter")
	Do $$$AssertEquals(##class(Readback.Units.Client).NeedsConversion(..Lab("2345-7", "HEMOLYZED", "mg/dL"), .tA), "skipped", "a non-numeric value is skipped")
	Do $$$AssertEquals(##class(Readback.Units.Client).NeedsConversion(..Lab("9999-9", "5", "mg/dL"), .tA), "skipped", "an analyte without a reference unit is skipped")
}

Method TestBuildRequestCarriesTheTextAsReceived()
{
	Do ##class(Readback.Units.Client).NeedsConversion(..Lab("2345-7", "540.10", "mg/dL"), .tA)
	Set tReq = ##class(Readback.Units.Client).BuildRequest(..Lab("2345-7", "540.10", "mg/dL"), tA)
	Do $$$AssertEquals(tReq.%classname, "com.readback.units.ConvertRequest", "the Java request class")
	Do $$$AssertEquals(tReq.value, "540.10", "the value text is kept exactly")
	Do $$$AssertEquals(tReq.unit, "mg/dL", "the unit as received")
	Do $$$AssertEquals(tReq.referenceUnit, "mmol/L", "the reference unit")
	Do $$$AssertEquals(tReq.molarMass, 180.156, "the molar mass of glucose")
	Do ##class(Readback.Units.Client).NeedsConversion(..Lab("2823-3", "6.9", "mEq/L"), .tK)
	Set tReq = ##class(Readback.Units.Client).BuildRequest(..Lab("2823-3", "6.9", "mEq/L"), tK)
	Do $$$AssertEquals(tReq.molarMass, "", "no molar mass for potassium")
}

Method TestParseEachAnswerKind()
{
	Set tC = ##class(Readback.Units.Client).ParseResponse(..Answer("converted", "7", "mmol/L"))
	Do $$$AssertEquals(tC.outcome, "converted", "converted")
	Do $$$AssertEquals(tC.value, "7", "with its value")
	Do $$$AssertEquals(tC.unit, "mmol/L", "and unit")
	Set tN = ##class(Readback.Units.Client).ParseResponse(..Answer("not-needed", "6.9", "mmol/L"))
	Do $$$AssertEquals(tN.outcome, "not-needed", "not-needed")
	Set tX = ##class(Readback.Units.Client).ParseResponse(..Answer("not-convertible", "", "", "cannot convert foo to mmol/L"))
	Do $$$AssertEquals(tX.outcome, "not-convertible", "not-convertible")
	Do $$$AssertTrue(tX.message["cannot convert", "with the library's message")
}

Method TestFailuresAreUnavailableWithAnEnglishMessageAndNoStack()
{
	Set tE = ##class(Readback.Units.Client).ParseResponse("", $System.Status.Error(5001, "gateway down"))
	Do $$$AssertEquals(tE.outcome, "unavailable", "an error status is unavailable")
	Do $$$AssertTrue(tE.message["gateway down", "the platform text is kept")
	Do $$$AssertTrue(tE.message'["<", "no stack or tag syntax leaks into the message")
	Do $$$AssertEquals(##class(Readback.Units.Client).ParseResponse("").outcome, "unavailable", "no answer is unavailable")
	Do $$$AssertEquals(##class(Readback.Units.Client).ParseResponse(..Answer("error", "", "", "unexpected failure: NullPointerException")).outcome, "unavailable", "an error inside the component is unavailable")
	Do $$$AssertEquals(##class(Readback.Units.Client).ParseResponse(..Answer("weird")).outcome, "unavailable", "an unknown outcome is unavailable")
}

Method TestErrorTextIsRedacted()
{
	Set ^||ReadbackTestKey = "test-key-value"
	Set tE = ##class(Readback.Units.Client).ParseResponse("", $System.Status.Error(5001, "failed with test-key-value in the text"))
	Kill ^||ReadbackTestKey
	Do $$$AssertTrue(tE.message'["test-key-value", "a key value never reaches the message")
}

Method TestEffectiveCopyLeavesTheStoredResultAlone()
{
	Set tLab = ..Lab("2345-7", "540", "mg/dL")
	Set tCopy = ##class(Readback.Units.Client).Effective(tLab, {"outcome":"converted","value":"29.97","unit":"mmol/L"})
	Do $$$AssertEquals(tCopy.ValueNumeric, 29.97, "the copy carries the converted value")
	Do $$$AssertEquals(tCopy.Unit, "mmol/L", "and the reference unit")
	Do $$$AssertEquals(tLab.ValueNumeric, 540, "the original value is untouched")
	Do $$$AssertEquals(tLab.Unit, "mg/dL", "and its unit")
	Set tSame = ##class(Readback.Units.Client).Effective(tLab, {"outcome":"not-convertible","value":"","unit":""})
	Do $$$AssertEquals(tSame.ValueNumeric, 540, "a failed conversion leaves the copy unchanged")
	Do $$$AssertEquals(tSame.Unit, "mg/dL", "with the original unit")
}

Method TestConvertedValueIsNotRoundedByTheCopy()
{
	Set tCopy = ##class(Readback.Units.Client).Effective(..Lab("2345-7", "540", "mg/dL"), {"outcome":"converted","value":"27.80000001","unit":"mmol/L"})
	Do $$$AssertTrue(tCopy.ValueNumeric > 27.8, "a value just above the critical limit stays above it in the copy")
}

}
