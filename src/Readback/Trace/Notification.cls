/// One event of the notification of a critical result: an alert opened, a delivery tried, acknowledged or failed, a level
/// raised, the last level reached, the read-back confirmed. Append-only; tied to the decision by the triage session id.
/// Detail never carries a key, a patient identifier or a value.
Class Readback.Trace.Notification Extends %Persistent
{

/// The triage session of the decision this event belongs to.
Property SessionId As %Integer [ Required ];

/// The platform's managed alert; empty for an event before the alert exists.
Property AlertId As %Integer;

Property Event As %String(VALUELIST = ",opened,delivery-attempt,delivery-receipt,delivery-failed,escalated,exhausted,confirmed") [ Required ];

/// The person the event concerns.
Property Recipient As %String(MAXLEN = 100);

/// The escalation level at the time. (Not named Level: that is a reserved word of the SQL.)
Property EscalationLevel As %Integer;

/// UTC. (Not named At: that is a reserved word of the SQL.)
Property EventTime As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

/// A fixed reason or the platform's text, redacted.
Property Detail As %String(MAXLEN = 300);

Index SessionIdx On SessionId;

Index AlertIdx On AlertId;

/// Writes one event. The detail passes through the redaction of credentials. Never raises: a trace row that cannot be
/// written must not stop an alert, and the failure goes to the console log without the text.
ClassMethod Add(pSessionId As %Integer, pAlertId As %Integer, pEvent As %String, pRecipient As %String = "", pLevel As %Integer = "", pDetail As %String = "") As %Status
{
	Set tSC = $$$OK
	Try {
		Set tRow = ..%New()
		Set tRow.SessionId = pSessionId, tRow.AlertId = pAlertId, tRow.Event = pEvent, tRow.Recipient = pRecipient, tRow.EscalationLevel = pLevel
		Set tRow.Detail = $Extract(##class(Readback.Config.Mode).Redact(pDetail), 1, 300)
		Set tSC = tRow.%Save()
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	If $System.Status.IsError(tSC) { Do ##class(%SYS.System).WriteToConsoleLog("Readback: a notification trace row was not written, code "_$System.Status.GetErrorCodes(tSC), 0, 1) }
	Quit tSC
}

Storage Default
{
<Data name="NotificationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionId</Value>
</Value>
<Value name="3">
<Value>AlertId</Value>
</Value>
<Value name="4">
<Value>Event</Value>
</Value>
<Value name="5">
<Value>Recipient</Value>
</Value>
<Value name="6">
<Value>EscalationLevel</Value>
</Value>
<Value name="7">
<Value>EventTime</Value>
</Value>
<Value name="8">
<Value>Detail</Value>
</Value>
</Data>
<DataLocation>^Readback.Trace.NotificationD</DataLocation>
<DefaultData>NotificationDefaultData</DefaultData>
<IdLocation>^Readback.Trace.NotificationD</IdLocation>
<IndexLocation>^Readback.Trace.NotificationI</IndexLocation>
<StreamLocation>^Readback.Trace.NotificationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
