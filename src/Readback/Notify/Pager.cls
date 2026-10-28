/// A simulated pager: the destination of the demonstration. Nothing leaves the machine. DeliveryMode is deliver (a receipt),
/// silent (accepted, no receipt) or fail (an error), so that escalation can be shown and tested for each way a delivery goes.
Class Readback.Notify.Pager Extends Ens.OutboundAdapter
{

Parameter SETTINGS = "DeliveryMode:Basic";

Property DeliveryMode As %String(VALUELIST = ",deliver,silent,fail") [ InitialExpression = "deliver" ];

/// Sends the text to the recipient. pReceipt is the acknowledgement of the channel; empty when it gave none.
Method Deliver(pRecipient As %String, pText As %String, Output pReceipt As %String) As %Status
{
	Set pReceipt = ""
	If ..DeliveryMode = "fail" { Quit $System.Status.Error(5001, "the pager is not reachable (simulated)") }
	If ..DeliveryMode = "silent" { Quit $$$OK }
	Set pReceipt = "pager-"_$Increment(^Readback("pagerReceipts"))
	Quit $$$OK
}

}
