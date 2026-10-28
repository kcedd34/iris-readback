/// Builds the request of the unit conversion component and reads its answer. The call itself is made by the
/// triage process (a business host); everything here is a pure helper so it can be tested alone.
Class Readback.Units.Client
{

Parameter RequestClass = "com.readback.units.ConvertRequest";

/// converted, not-needed, not-convertible, unavailable (the component failed or did not answer) or skipped
/// (nothing to convert: the value is not numeric or the analyte has no reference unit).
ClassMethod NeedsConversion(pLab As Readback.Msg.LabResult, Output pAnalyte As Readback.Config.Analyte) As %String
{
	Set pAnalyte = ""
	Quit:pLab.ValueNumeric="" "skipped"
	Quit:'##class(Readback.Config.Analyte).CodeIdxExists(pLab.AnalyteCode, .tId) "skipped"
	Set pAnalyte = ##class(Readback.Config.Analyte).%OpenId(tId)
	Quit:'$IsObject(pAnalyte) "skipped"
	Quit:$ZStrip(pLab.Unit, "<>W")=pAnalyte.ReferenceUnit "not-needed"
	Quit "convert"
}

/// The PEX request for a result and its analyte. The value is sent as the text received, never as a binary number.
ClassMethod BuildRequest(pLab As Readback.Msg.LabResult, pAnalyte As Readback.Config.Analyte) As EnsLib.PEX.Message
{
	Set tMsg = ##class(EnsLib.PEX.Message).%New(..#RequestClass)
	Set tMsg.value = $ZStrip(pLab.ValueText, "<>W")
	Set tMsg.unit = pLab.Unit
	Set tMsg.referenceUnit = pAnalyte.ReferenceUnit
	Set tMsg.molarMass = $Select(pAnalyte.MolarMass'="":pAnalyte.MolarMass, 1:"")
	Quit tMsg
}

/// Reads the answer of the component. The result is a %DynamicObject with outcome, value, unit and message.
/// An error status, a missing or unreadable answer, or a failure inside the component is outcome "unavailable".
ClassMethod ParseResponse(pResponse As %RegisteredObject, pStatus As %Status = 1) As %DynamicObject
{
	Set tOut = {"outcome":"unavailable","value":"","unit":"","message":""}
	If $System.Status.IsError(pStatus) {
		Set tOut.message = "unit conversion unavailable: "_##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(pStatus))
		Quit tOut
	}
	If '$IsObject(pResponse) {
		Set tOut.message = "unit conversion unavailable: no answer"
		Quit tOut
	}
	Set tText = ""
	Try { Set tText = pResponse.%json } Catch ex { Set tText = "" }
	Set tJson = ""
	Try { Set tJson = {}.%FromJSON(tText) } Catch ex { Set tJson = "" }
	If '$IsObject(tJson) {
		Set tOut.message = "unit conversion unavailable: the answer could not be read"
		Quit tOut
	}
	Set tOutcome = tJson.outcome
	If $ListFind($ListBuild("converted", "not-needed", "not-convertible"), tOutcome) = 0 {
		Set tOut.message = "unit conversion unavailable: "_$Select(tJson.message'="":tJson.message, 1:"the component reported an error")
		Quit tOut
	}
	Set tOut.outcome = tOutcome, tOut.value = tJson.value, tOut.unit = tJson.unit, tOut.message = tJson.message
	Quit tOut
}

/// A copy of the stored result carrying the converted value and the reference unit when the conversion
/// succeeded (or was not needed); otherwise an unchanged copy. The stored result is never modified.
ClassMethod Effective(pLab As Readback.Msg.LabResult, pConv As %DynamicObject) As Readback.Msg.LabResult
{
	Set tCopy = pLab.%ConstructClone()
	If (pConv.outcome = "converted") || (pConv.outcome = "not-needed") {
		Set tCopy.ValueNumeric = pConv.value
		Set tCopy.Unit = pConv.unit
	}
	Quit tCopy
}

}
