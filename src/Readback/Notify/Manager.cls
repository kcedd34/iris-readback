Include Ensemble

/// The platform's alert manager, as the production item Ens.Alert. It creates the managed alert exactly as the platform does;
/// the only change is the documented callback that sets the first person and a first window in seconds (the platform's own
/// setting is whole minutes). Escalation is not done here.
Class Readback.Notify.Manager Extends Ens.Alerting.AlertManager
{

/// Only the alerts of critical results become managed alerts. Any other alert of the production (the platform raises one for
/// every logged alert) stays what it was, an entry of the event log, and is not escalated to the pager.
Method OnProcessAlertRequest(pAlertRequest As Ens.AlertRequest, Output pProcessingComplete As %Boolean) As %Status
{
	Set pProcessingComplete = (##class(Readback.Notify.Raise).IsOurs(pAlertRequest.AlertText) = 0)
	Quit $$$OK
}

Method OnCreateManagedAlert(pAlertRequest As Ens.AlertRequest, Output pManagedAlert As Ens.Alerting.ManagedAlert, pInitialOwner As %String = "") As %Status
{
	Set tSC = ##super(pAlertRequest, .pManagedAlert, pInitialOwner)
	Quit:$$$ISERR(tSC) tSC
	Set tFirst = ##class(Readback.Notify.Escalation).RecipientFor(0)
	If tFirst '= "" {
		Set pManagedAlert.CurrentOwner = tFirst
		Set pManagedAlert.NextActionTime = $System.SQL.DATEADD("ss", ##class(Readback.Notify.Escalation).FirstWindow(), $$$timeUTC)
		Set tSC = pManagedAlert.UpdateNextMonitorTime(0)
		Quit:$$$ISERR(tSC) tSC
	}
	// The platform saves the alert again after this callback; it is saved here so that the trace row can name it.
	Set tSC = pManagedAlert.%Save()
	Quit:$$$ISERR(tSC) tSC
	Do ##class(Readback.Trace.Notification).Add(pAlertRequest.SessionId, pManagedAlert.%Id(), "opened", tFirst, 0, "alert opened for the first person on the list")
	Quit $$$OK
}

}
