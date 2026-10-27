/// Normalization of a valid HL7 ORU^R01 into Readback.Msg.LabResult.
Class Readback.Test.NormalizationTest Extends %UnitTest.TestCase
{

ClassMethod Build(pSegments As %List) As EnsLib.HL7.Message
{
	Set tText = ""
	Set tPtr = 0
	While $ListNext(pSegments, tPtr, tSeg) { Set tText = tText_tSeg_$Char(13) }
	Quit ##class(EnsLib.HL7.Message).ImportFromString(tText)
}

ClassMethod Msh(pId As %String = "TEST0001", pType As %String = "ORU^R01") As %String
{
	Quit "MSH|^~\&|SYNLAB|SYNFAC|READBACK|SYNFAC|20260301083000||"_pType_"|"_pId_"|P|2.5"
}

Method TestValidMessage()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001^^^SYN^MR||SYNTHETIC^PATIENT", "OBR|1|||2823-3^Potassium^LN|||20260301080000", "OBX|1|NM|2823-3^Potassium^LN||6.9|mmol/L|3.5-5.1|HH|||F"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusOK(tSC, "valid message is accepted")
	Do $$$AssertEquals(tReply, "AA", "reply code is AA")
	Do $$$AssertEquals(tLab.MessageControlId, "TEST0001", "MessageControlId kept as received")
	Do $$$AssertEquals(tLab.PatientId, "SYN0000001", "PatientId taken from PID-3")
	Do $$$AssertEquals(tLab.AnalyteCode, "2823-3", "AnalyteCode taken from OBX-3")
	Do $$$AssertEquals(tLab.ValueText, "6.9", "ValueText keeps the original text")
	Do $$$AssertEquals(tLab.ValueNumeric, 6.9, "ValueNumeric is numeric when parseable")
	Do $$$AssertEquals(tLab.Unit, "mmol/L", "Unit is the original unit, not converted")
	Do $$$AssertEquals(tLab.ReferenceRange, "3.5-5.1", "ReferenceRange from OBX-7")
	Do $$$AssertEquals(tLab.CollectedAt, "2026-03-01 08:00:00", "CollectedAt in ISO form")
	Do $$$AssertEquals(tLab.Source, "file", "Source recorded")
	Do $$$AssertTrue(tLab.RawHL7["OBX|1|NM|2823-3", "RawHL7 is always preserved")
}

Method TestNonNumericValueKeepsText()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001", "OBX|1|ST|2345-7^Glucose^LN||HEMOLYZED|mg/dL"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "tcp", .tLab, .tReply)
	Do $$$AssertStatusOK(tSC, "non-numeric value is still accepted")
	Do $$$AssertEquals(tLab.ValueText, "HEMOLYZED", "original text kept")
	Do $$$AssertEquals(tLab.ValueNumeric, "", "no numeric value")
}

Method TestSampleIndexAndSegmentOrder()
{
	// Segments out of the usual order, optional OBR absent.
	Set tMsg = ..Build($ListBuild(..Msh(), "OBX|1|NM|718-7^Hemoglobin^LN||8.1|g/dL", "OBX|2|NM|HEMOLYSIS_INDEX^Hemolysis index^L||120|index", "PID|1||SYN0000002"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusOK(tSC, "order of segments does not matter and OBR is optional")
	Do $$$AssertEquals(tLab.AnalyteCode, "718-7", "analyte is the first non-index OBX")
	Do $$$AssertEquals(tLab.SampleIndices.Count(), 1, "one sample index recorded")
	Do $$$AssertEquals(tLab.SampleIndices.GetAt(1), "HEMOLYSIS_INDEX=120", "index recorded as code=value")
	Do $$$AssertEquals(tLab.CollectedAt, "", "optional CollectedAt stays empty")
}

Method TestDuplicateMessagesAreIndependent()
{
	Set tMsg = ..Build($ListBuild(..Msh("DUP0001"), "PID|1||SYN0000003", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Do ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab1, .tReply1)
	Do ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab2, .tReply2)
	Do $$$AssertTrue(tLab1 '= tLab2, "each submission yields its own record")
	Do $$$AssertEquals(tLab1.MessageControlId, tLab2.MessageControlId, "same control id is processed again, not dropped")
}

Method TestBirthDateAndAge()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001^^^SYN^MR||SYNTHETIC^PATIENT||19700101|F", "OBR|1|||2823-3^Potassium^LN|||20260301080000", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusOK(tSC, "message with a date of birth is accepted")
	Do $$$AssertEquals($ZDate(tLab.BirthDate, 3), "1970-01-01", "BirthDate taken from PID-7")
	Do $$$AssertEquals(tLab.AgeYears, 56, "age in whole years at the collection time")
}

Method TestAgeBeforeBirthday()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001||SYNTHETIC^PATIENT||19700301|F", "OBR|1|||2823-3^Potassium^LN|||20260228080000", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Do ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertEquals(tLab.AgeYears, 55, "birthday not reached yet, one year less")
}

Method TestMissingBirthDate()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Do ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertEquals(tLab.BirthDate, "", "no BirthDate when PID-7 is absent")
	Do $$$AssertEquals(tLab.AgeYears, "", "age unknown when BirthDate is absent")
}

Method TestUnparsableBirthDate()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001||SYNTHETIC^PATIENT||notadate|F", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusOK(tSC, "an unparsable date of birth does not reject the message")
	Do $$$AssertEquals(tLab.BirthDate, "", "unparsable date kept out")
	Do $$$AssertEquals(tLab.AgeYears, "", "age unknown")
}

Method TestBirthDateAfterCollection()
{
	Set tMsg = ..Build($ListBuild(..Msh(), "PID|1||SYN0000001||SYNTHETIC^PATIENT||20300101|F", "OBR|1|||2823-3^Potassium^LN|||20260301080000", "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Do ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertEquals(tLab.AgeYears, "", "date of birth after the collection time gives no age")
}

}
