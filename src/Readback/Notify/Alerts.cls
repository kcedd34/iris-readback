Include Ensemble

/// The product's view of its managed alerts: find the open alert of a case, close it on the matching read-back, list the open
/// ones and count them. Closing goes through the platform's own update; this class keeps no state of its own.
Class Readback.Notify.Alerts
{

/// The id of the open alert of the session, or "".
ClassMethod FindOpen(pSessionId As %Integer) As %Integer
{
	Set tPrefix = ##class(Readback.Notify.Raise).#PREFIX
	&sql(SELECT TOP 1 ID INTO :tId FROM Ens_Alerting.ManagedAlert WHERE SessionId = :pSessionId AND IsOpen = 1 AND AlertText %STARTSWITH :tPrefix ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Quit tId
}

/// Closes the open alert of the session because the read-back matched, and records who confirmed. Does nothing when the
/// session has no open alert. Never raises: closing the alert must not undo a confirmation.
ClassMethod Close(pSessionId As %Integer, pUser As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tId = ..FindOpen(pSessionId)
		If tId '= "" {
			Set tLevel = +##class(Ens.Alerting.ManagedAlert).%OpenId(tId).EscalationLevel
			Kill tNew
			Set tNew("IsOpen") = 0
			Set tSC = ##class(Ens.Alerting.ManagedAlert).UpdateManagedAlert(tId, $$$eAlertActionOpenChange, .tNew, "read-back confirmed")
			If $$$ISOK(tSC) {
				Do ##class(Readback.Trace.Notification).Add(pSessionId, tId, "confirmed", pUser, tLevel, "the repeated value matched the original")
			} Else {
				Do ##class(%SYS.System).WriteToConsoleLog("Readback: the alert was not closed: "_$Extract(##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(tSC)), 1, 300), 0, 1)
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
		Do ##class(%SYS.System).WriteToConsoleLog("Readback: the alert could not be closed, code "_$System.Status.GetErrorCodes(tSC), 0, 1)
	}
	Quit tSC
}

/// The open alerts as a list of {alertId, controlId, level, owner, alerted, nextActionTime, state}. state is open, or exhausted
/// at the last level. owner is the platform's current owner (the first person); alerted is the person of the current level.
ClassMethod Open() As %DynamicArray
{
	Set tList = []
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, EscalationLevel, CurrentOwner, NextActionTime FROM Ens_Alerting.ManagedAlert WHERE IsOpen = 1 AND AlertText %STARTSWITH ? ORDER BY ID", ##class(Readback.Notify.Raise).#PREFIX)
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("alerts query failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tLevel = +tRS.%Get("EscalationLevel")
		Set tItem = {}
		Set tItem.alertId = +tRS.%Get("ID")
		Set tItem.controlId = ..ControlIdOf(tRS.%Get("SessionId"))
		Set tItem.level = tLevel
		Set tItem.owner = tRS.%Get("CurrentOwner")
		Set tItem.alerted = ##class(Readback.Notify.Escalation).RecipientFor(tLevel)
		Set tItem.nextActionTime = tRS.%Get("NextActionTime")
		Set tItem.state = $Select(##class(Readback.Notify.Escalation).IsExhausted(tLevel):"exhausted", 1:"open")
		Do tList.%Push(tItem)
	}
	Quit tList
}

/// {open, byLevel: {"0": n, ...}, exhausted, closed} over the alerts of critical results.
ClassMethod Counts() As %DynamicObject
{
	Set tRes = {"open":0, "byLevel":{}, "exhausted":0, "closed":0}
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT IsOpen, EscalationLevel, COUNT(*) AS N FROM Ens_Alerting.ManagedAlert WHERE AlertText %STARTSWITH ? GROUP BY IsOpen, EscalationLevel", ##class(Readback.Notify.Raise).#PREFIX)
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("alert counts query failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tN = +tRS.%Get("N"), tLevel = +tRS.%Get("EscalationLevel")
		If +tRS.%Get("IsOpen") {
			Set tRes.open = tRes.open + tN
			Do tRes.byLevel.%Set(tLevel, +tRes.byLevel.%Get(tLevel) + tN)
			If ##class(Readback.Notify.Escalation).IsExhausted(tLevel) { Set tRes.exhausted = tRes.exhausted + tN }
		} Else {
			Set tRes.closed = tRes.closed + tN
		}
	}
	Quit tRes
}

/// The message id of the decision of a session, or "".
ClassMethod ControlIdOf(pSessionId As %Integer) As %String
{
	&sql(SELECT TOP 1 MessageControlId INTO :tId FROM Readback_Trace.Decision WHERE SessionId = :pSessionId ORDER BY ID DESC)
	Quit $Select(SQLCODE=0:tId, 1:"")
}

}
