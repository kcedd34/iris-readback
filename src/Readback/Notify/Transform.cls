Include Ensemble

/// The notification transform of the platform's notification manager: the person to alert is the one of the alert's level.
/// With no escalation file loaded it adds no target, and the manager falls back to the production's default operation and
/// recipients.
Class Readback.Notify.Transform Extends %RegisteredObject
{

ClassMethod Transform(pNotificationRequest As Ens.Alerting.NotificationRequest, ByRef pNotificationContext As Ens.Alerting.Context.Notify) As %Status
{
	Quit:'##class(Readback.Notify.Escalation).IsLoaded() $$$OK
	Set tPerson = ##class(Readback.Notify.Escalation).RecipientFor(+pNotificationRequest.ManagedAlert.EscalationLevel)
	Set tTarget = ##class(Ens.Alerting.NotificationTarget).%New()
	Set tTarget.TargetConfigName = "Readback.Notify.Pager"
	Do tTarget.AlertDestinations.Insert(tPerson)
	Do pNotificationContext.Targets.Insert(tTarget)
	Quit $$$OK
}

}
