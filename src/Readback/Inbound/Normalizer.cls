/// Validates a received HL7 message and builds the normalized Readback.Msg.LabResult.
/// Walks segments by name, so segment order does not matter and optional fields may be absent.
Class Readback.Inbound.Normalizer
{

/// Codes in OBX-3.1 that describe sample quality instead of an analyte.
Parameter SAMPLEINDEXCODES = "HEMOLYSIS_INDEX,LIPEMIA_INDEX,ICTERUS_INDEX";

/// Returns an error status when the message is rejected. pReply is the HL7 acknowledgement code:
/// AR for the wrong message type, AE for a valid ORU^R01 missing a required field.
ClassMethod Normalize(pHL7 As EnsLib.HL7.Message, pSource As %String, Output pLab As Readback.Msg.LabResult, Output pReply As %String) As %Status
{
	Set pLab = $$$NULLOREF, pReply = "AA"
	If '$IsObject(pHL7) {
		Set pReply = "AR"
		Quit $$$ERROR($$$GeneralError, "Rejected: the received text could not be parsed as an HL7 message")
	}
	Set tMSH = pHL7.getSegmentByIndex(1)
	Set tType = $Select($IsObject(tMSH):tMSH.GetValueAt("9.1")_"^"_tMSH.GetValueAt("9.2"), 1:"^")
	If tType '= "ORU^R01" {
		Set pReply = "AR"
		Quit $$$ERROR($$$GeneralError, "Rejected: expected message type ORU^R01 but received '"_tType_"'")
	}
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = tMSH.GetValueAt("10")
	Set tLab.Source = pSource
	Set tLab.RawHL7 = pHL7.OutputToString()
	Set tAnalyteSeen = 0
	For i = 1:1:pHL7.SegCount {
		Set tSeg = pHL7.getSegmentByIndex(i)
		Continue:'$IsObject(tSeg)
		Set tName = tSeg.Name
		If tName = "PID", tLab.PatientId = "" {
			Set tLab.PatientId = tSeg.GetValueAt("3.1")
		} ElseIf tName = "OBR", tLab.CollectedAt = "" {
			Set tLab.CollectedAt = ..ToTimeStamp(tSeg.GetValueAt("7"))
		} ElseIf tName = "OBX" {
			Set tCode = tSeg.GetValueAt("3.1"), tValue = tSeg.GetValueAt("5")
			If (","_..#SAMPLEINDEXCODES_",") [ (","_tCode_",") {
				Do tLab.SampleIndices.Insert(tCode_"="_tValue)
			} ElseIf 'tAnalyteSeen {
				Set tAnalyteSeen = 1
				Set tLab.AnalyteCode = tCode
				Set tLab.ValueText = tValue
				Set:$IsValidNum(tValue) tLab.ValueNumeric = tValue
				Set tLab.Unit = tSeg.GetValueAt("6")
				Set tLab.ReferenceRange = tSeg.GetValueAt("7")
			}
		}
	}
	Set tMissing = ""
	Set:(tLab.MessageControlId = "") tMissing = tMissing_" MSH-10"
	Set:(tLab.PatientId = "") tMissing = tMissing_" PID-3"
	Set:(tLab.AnalyteCode = "") tMissing = tMissing_" OBX-3"
	Set:(tLab.ValueText = "") tMissing = tMissing_" OBX-5"
	If tMissing '= "" {
		Set pReply = "AE"
		Quit $$$ERROR($$$GeneralError, "Rejected: missing required field(s):"_tMissing)
	}
	Set pLab = tLab
	Quit $$$OK
}

/// HL7 timestamp yyyymmdd[hh[mm[ss]]] to ISO form; anything else is returned unchanged.
ClassMethod ToTimeStamp(pHL7Time As %String) As %String
{
	Quit:pHL7Time'?8.14N pHL7Time
	Set tDate = $Extract(pHL7Time, 1, 4)_"-"_$Extract(pHL7Time, 5, 6)_"-"_$Extract(pHL7Time, 7, 8)
	Set tHH = $Extract(pHL7Time, 9, 10), tMM = $Extract(pHL7Time, 11, 12), tSS = $Extract(pHL7Time, 13, 14)
	Quit tDate_" "_$Select(tHH="":"00", 1:tHH)_":"_$Select(tMM="":"00", 1:tMM)_":"_$Select(tSS="":"00", 1:tSS)
}

}
