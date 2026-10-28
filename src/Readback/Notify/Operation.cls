Include Ensemble

/// The delivery channel of the critical-result notification: delivers the platform's notification through the pager and keeps
/// the delivery receipt as a fact apart from the confirmation. A delivery never changes the alert and never closes it; only
/// the matching read-back does. It always returns success to the engine after recording, so the engine does not resend on
/// its own: a delivery that failed or went unanswered is handled by the platform's escalation when the time runs out.
Class Readback.Notify.Operation Extends Ens.Alerting.NotificationOperation
{

Parameter ADAPTER = "Readback.Notify.Pager";

Property Adapter As Readback.Notify.Pager;

Parameter INVOCATION = "Queue";

Method OnNotify(pRequest As Ens.Alerting.NotificationRequest, Output pResponse As Ens.Response) As %Status
{
	Set pResponse = $$$NULLOREF
	Set tAlert = pRequest.ManagedAlert
	Quit:'$IsObject(tAlert) $$$OK
	Set tSession = tAlert.SessionId, tId = tAlert.%Id(), tLevel = +tAlert.EscalationLevel
	Set tText = ..TextFor(pRequest, tAlert)
	For i = 1:1:pRequest.AlertDestinations.Count() {
		Set tPerson = pRequest.AlertDestinations.GetAt(i)
		Do ##class(Readback.Trace.Notification).Add(tSession, tId, "delivery-attempt", tPerson, tLevel, "sent through the pager")
		Set tReceipt = ""
		Try {
			Set tSC = ..Adapter.Deliver(tPerson, tText, .tReceipt)
		} Catch ex {
			Set tSC = $System.Status.Error(5001, "the channel raised an error")
		}
		If $System.Status.IsError(tSC) {
			Do ##class(Readback.Trace.Notification).Add(tSession, tId, "delivery-failed", tPerson, tLevel, "channel error: "_$System.Status.GetErrorText(tSC))
		} ElseIf tReceipt = "" {
			Do ##class(Readback.Trace.Notification).Add(tSession, tId, "delivery-failed", tPerson, tLevel, "not acknowledged")
		} Else {
			Do ##class(Readback.Trace.Notification).Add(tSession, tId, "delivery-receipt", tPerson, tLevel, "receipt "_tReceipt)
		}
	}
	Quit $$$OK
}

/// The alert text, plus the platform's own line for a reminder or an escalation. The first notification has no such line: the
/// platform words it as a reminder, which it is not. No patient identifier and no value is in it.
Method TextFor(pRequest As Ens.Alerting.NotificationRequest, pAlert As Ens.Alerting.ManagedAlert) As %String
{
	Set tText = pAlert.AlertText
	If (pRequest.NotificationType = $$$eAlertNotificationReminder) || (pRequest.NotificationType = $$$eAlertNotificationEscalationChange) {
		Do ..GetUpdateText(pRequest, .tUpdate)
		Set tText = tText_$Char(10)_$Get(tUpdate)
	}
	Quit tText
}

XData MessageMap
{
<MapItems>
<MapItem MessageType="Ens.Alerting.NotificationRequest">
<Method>OnNotify</Method>
</MapItem>
</MapItems>
}

}
