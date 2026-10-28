Include Ensemble

/// The platform's overdue-alert monitor. The documented context callback is the only change: it names the next level and the
/// next time from the escalation file, and the platform applies them, notifies and keeps its action log. At the last level
/// the level does not rise: the platform sends a reminder to the last person and the alert stays open.
Class Readback.Notify.Monitor Extends Ens.Alerting.AlertMonitor
{

Method GetOverdueAlertContext(pManagedAlert As Ens.Alerting.ManagedAlert, Output pOverdueContext As Ens.Alerting.Context.OverdueAlert) As %Status
{
	Set tSC = ##super(pManagedAlert, .pOverdueContext)
	Quit:$$$ISERR(tSC) tSC
	Quit:'##class(Readback.Notify.Escalation).IsLoaded() $$$OK
	Set tLevel = +pManagedAlert.EscalationLevel
	Set tNext = ##class(Readback.Notify.Escalation).NextLevel(tLevel)
	Set pOverdueContext.NewEscalationLevel = tNext
	Set pOverdueContext.NewNextActionTime = $System.SQL.DATEADD("ss", ##class(Readback.Notify.Escalation).Window(), $$$timeUTC)
	If tNext > tLevel {
		Do ##class(Readback.Trace.Notification).Add(pManagedAlert.SessionId, pManagedAlert.%Id(), "escalated", ##class(Readback.Notify.Escalation).RecipientFor(tNext), tNext, "no confirmation within the window")
	} ElseIf '..ExhaustedRecorded(pManagedAlert.%Id()) {
		Do ##class(Readback.Trace.Notification).Add(pManagedAlert.SessionId, pManagedAlert.%Id(), "exhausted", ##class(Readback.Notify.Escalation).RecipientFor(tLevel), tLevel, "the last person was alerted and nobody confirmed; the alert stays open")
	}
	Quit $$$OK
}

/// True when the alert already has its one `exhausted` row.
ClassMethod ExhaustedRecorded(pAlertId As %Integer) As %Boolean
{
	&sql(SELECT COUNT(*) INTO :tN FROM Readback_Trace.Notification WHERE AlertId = :pAlertId AND Event = 'exhausted')
	Quit (SQLCODE = 0) && (tN > 0)
}

}
