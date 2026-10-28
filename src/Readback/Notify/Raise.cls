Include Ensemble

/// Raises the alert of a critical result from the triage process, through the platform's own SendAlert. The alert is an
/// addition to the read-back task, never a condition of it: whatever goes wrong here, the task is there.
Class Readback.Notify.Raise
{

/// The start of the text of every alert this product raises; the manager only turns alerts that start with it into managed alerts.
Parameter PREFIX = "Critical result: case ";

/// The text holds the case id, the analyte code and the severity. No patient identifier and no value.
ClassMethod TextFor(pControlId As %String, pAnalyte As %String, pSeverity As %String) As %String
{
	Quit ..#PREFIX_pControlId_", analyte "_pAnalyte_", severity "_pSeverity_". Open the read-back task."
}

ClassMethod IsOurs(pText As %String) As %Boolean
{
	Quit $Extract(pText, 1, $Length(..#PREFIX)) = ..#PREFIX
}

/// Sends the alert request for the case. Returns the status of the send; a missing escalation file or a production without the
/// alert manager is reported to the console log and is not an error.
ClassMethod ForCase(pHost As Ens.BusinessProcess, pControlId As %String, pAnalyte As %String, pSeverity As %String) As %Status
{
	Set tSC = $$$OK
	Try {
		If '##class(Readback.Notify.Escalation).IsLoaded() {
			Do ##class(%SYS.System).WriteToConsoleLog("Readback: no alert raised, the escalation file is not loaded", 0, 1)
		} ElseIf $Get($$$DispatchNameToConfigName("Ens.Alert")) = "" {
			Do ##class(%SYS.System).WriteToConsoleLog("Readback: no alert raised, the production has no Ens.Alert item", 0, 1)
		} Else {
			Set tReq = ##class(Ens.AlertRequest).%New()
			Set tReq.AlertText = ..TextFor(pControlId, pAnalyte, pSeverity)
			Set tReq.SourceConfigName = $$$JobConfigName
			Set tReq.AlertTime = $$$timeUTC
			Set tReq.SessionId = +$$$JobSessionId
			Set tSC = pHost.SendAlert(tReq)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
		Do ##class(%SYS.System).WriteToConsoleLog("Readback: the alert could not be raised, code "_$System.Status.GetErrorCodes(tSC), 0, 1)
	}
	Quit tSC
}

}
