/// Receives HL7 ORU^R01 over TCP, normalizes and persists them, and hands the result to the log operation.
/// Replies AA when accepted, AE for a missing required field and AR for the wrong message type.
Class Readback.Inbound.HL7TCP Extends EnsLib.HL7.Service.TCPService
{

Parameter TARGET = "Readback.Outbound.LogOperation";

Method standardOnProcessInput(pDocIn As EnsLib.HL7.Message, Output pDocOut As EnsLib.HL7.Message) As %Status
{
	Set pDocOut = $$$NULLOREF
	Set tSC = ##class(Readback.Inbound.Normalizer).Normalize(pDocIn, "tcp", .tLab, .tReply)
	If $$$ISERR(tSC) {
		$$$LOGERROR($$$StatusText(tSC))
	} Else {
		Set tSC = tLab.%Save()
		Set:$$$ISOK(tSC) tSC = ..SendRequestAsync(..#TARGET, tLab)
		Set:$$$ISERR(tSC) tReply = "AE"
	}
	Set tAckStatus = $$$OK
	Set pDocOut = ..reportReply(pDocIn, tReply, .tAckStatus)
	Quit tSC
}

}
