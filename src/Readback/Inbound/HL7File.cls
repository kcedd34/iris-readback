/// Receives HL7 ORU^R01 files, normalizes and persists them, and hands the result to the log operation.
Class Readback.Inbound.HL7File Extends EnsLib.HL7.Service.FileService
{

Parameter TARGET = "Readback.Triage";

Method standardOnProcessInput(pDocIn As EnsLib.HL7.Message, Output pDocOut As EnsLib.HL7.Message) As %Status
{
	Set pDocOut = $$$NULLOREF
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(pDocIn, "file", .tLab, .tReply)
	If $$$ISERR(tSC) {
		$$$LOGERROR($$$StatusText(tSC))
		Quit tSC
	}
	Set tSC = tLab.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit ..SendRequestAsync(..#TARGET, tLab, 0)
}

}
