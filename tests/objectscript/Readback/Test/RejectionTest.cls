/// Rejection of messages that must never become a Readback.Msg.LabResult.
Class Readback.Test.RejectionTest Extends %UnitTest.TestCase
{

Method TestWrongMessageType()
{
	Set tMsg = ##class(Readback.Test.NormalizationTest).Build($ListBuild(##class(Readback.Test.NormalizationTest).Msh("ADT0001", "ADT^A01"), "PID|1||SYN0000001"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "tcp", .tLab, .tReply)
	Do $$$AssertStatusNotOK(tSC, "wrong message type is rejected")
	Do $$$AssertEquals(tReply, "AR", "reply code is AR")
	Do $$$AssertTrue('$IsObject(tLab), "no lab result is created")
	Do $$$AssertTrue($system.Status.GetErrorText(tSC)["expected message type ORU^R01", "reason is in English and names the type")
}

Method TestMissingRequiredFields()
{
	Set tMsg = ##class(Readback.Test.NormalizationTest).Build($ListBuild(##class(Readback.Test.NormalizationTest).Msh(), "PID|1||SYN0000001", "OBR|1|||2823-3^Potassium^LN"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusNotOK(tSC, "message without OBX is rejected")
	Do $$$AssertEquals(tReply, "AE", "reply code is AE")
	Do $$$AssertTrue('$IsObject(tLab), "no lab result is created")
	Do $$$AssertTrue($system.Status.GetErrorText(tSC)["OBX-3", "reason names the missing field")
}

Method TestMissingPatient()
{
	Set tMsg = ##class(Readback.Test.NormalizationTest).Build($ListBuild(##class(Readback.Test.NormalizationTest).Msh(), "OBX|1|NM|2823-3^Potassium^LN||4.2|mmol/L"))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusNotOK(tSC, "message without PID-3 is rejected")
	Do $$$AssertTrue($system.Status.GetErrorText(tSC)["PID-3", "reason names PID-3")
}

Method TestNoMessageHeader()
{
	Set tMsg = ##class(EnsLib.HL7.Message).ImportFromString("PID|1||SYN0000001"_$Char(13))
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(tMsg, "file", .tLab, .tReply)
	Do $$$AssertStatusNotOK(tSC, "text without MSH is rejected")
	Do $$$AssertTrue('$IsObject(tLab), "no lab result is created")
}

}
