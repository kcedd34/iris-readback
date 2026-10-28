Include Ensemble

/// Closing the alert: only a matching read-back closes it, a divergent one leaves it open, a delivery receipt alone never does.
Class Readback.Test.AlertCloseTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

ClassMethod Clean()
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Readback_Trace.Notification WHERE SessionId BETWEEN 987100 AND 987199")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Alerting.ManagedAlert WHERE SessionId BETWEEN 987100 AND 987199")
	&sql(DELETE FROM Readback_Trace.ReadbackAttempt WHERE TaskId LIKE 'T-UNIT-AC%')
	&sql(DELETE FROM Readback_Trace.Decision WHERE TaskId LIKE 'T-UNIT-AC%')
	&sql(DELETE FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'RT-UNIT-AC%')
}

/// A result of 6.9, its decision trace, its read-back task and its open alert, all on one session.
ClassMethod Case(pN As %Integer) As %String
{
	Set tSession = 987100 + pN, tControl = "RT-UNIT-AC"_pN, tTask = "T-UNIT-AC"_pN
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = tControl, tLab.PatientId = "SYN0000098", tLab.AnalyteCode = "2823-3", tLab.ValueText = "6.9", tLab.Source = "file"
	Do tLab.%Save()
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = tControl, tTrace.SessionId = tSession, tTrace.TaskId = tTask
	Do tTrace.%Save()
	Set tAlert = ##class(Ens.Alerting.ManagedAlert).%New()
	Set tAlert.AlertText = ##class(Readback.Notify.Raise).TextFor(tControl, "2823-3", 3)
	Set tAlert.SessionId = tSession, tAlert.EscalationLevel = 1, tAlert.IsOpen = 1, tAlert.CurrentOwner = "communicator1"
	Set tAlert.AlertTime = $$$timeUTC
	Do tAlert.%Save()
	Quit tTask
}

ClassMethod IsOpen(pN As %Integer) As %Boolean
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT IsOpen FROM Ens_Alerting.ManagedAlert WHERE SessionId = ?", 987100 + pN)
	Do tRS.%Next()
	Quit +tRS.%Get("IsOpen")
}

ClassMethod Confirmed(pN As %Integer) As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Readback_Trace.Notification WHERE SessionId = ? AND Event = 'confirmed'", 987100 + pN)
	Do tRS.%Next()
	Quit +tRS.%GetData(1)
}

Method TestAMatchingReadbackClosesTheAlert()
{
	Set tTask = ..Case(1)
	Do $$$AssertTrue(..IsOpen(1), "the alert starts open")
	Do $$$AssertStatusOK(##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator2", "Dr. Example", "6.90"), "the matching value passes")
	Do $$$AssertNotTrue(..IsOpen(1), "the alert is closed")
	Do $$$AssertEquals(..Confirmed(1), 1, "one confirmed row")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Recipient, EscalationLevel FROM Readback_Trace.Notification WHERE SessionId = 987101 AND Event = 'confirmed'")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.%Get("Recipient"), "communicator2", "the confirming person is recorded")
	Do $$$AssertEquals(tRS.%Get("EscalationLevel"), 1, "with the level the alert had")
	Set tAlert = ##class(Ens.Alerting.ManagedAlert).%OpenId($Order(^Ens.Alerting.ManagedAlertD(""), -1))
	Do $$$AssertTrue(tAlert.Actions.Count() > 0, "the platform's own action list records the close")
}

Method TestADivergentReadbackLeavesTheAlertOpen()
{
	Set tTask = ..Case(2)
	Do $$$AssertStatusNotOK(##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "Dr. Example", "9.6"), "a divergent value is blocked")
	Do $$$AssertTrue(..IsOpen(2), "the alert stays open")
	Do $$$AssertEquals(..Confirmed(2), 0, "and no confirmed row is written")
	Do $$$AssertStatusNotOK(##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "", "6.9"), "a match with nobody told is blocked too")
	Do $$$AssertTrue(..IsOpen(2), "the alert is still open")
}

Method TestADeliveryReceiptAloneNeverCloses()
{
	Set tTask = ..Case(3)
	Do ##class(Readback.Trace.Notification).Add(987103, "", "delivery-receipt", "communicator1", 1, "receipt pager-1")
	Do $$$AssertTrue(..IsOpen(3), "a receipt row leaves the alert open")
	Do $$$AssertEquals(..Confirmed(3), 0, "and is not a confirmation")
}

Method TestClosingASessionWithNoAlertDoesNothing()
{
	Do $$$AssertStatusOK(##class(Readback.Notify.Alerts).Close(987199, "communicator1"), "no alert is not an error")
	Do $$$AssertEquals(..Confirmed(99), 0, "and nothing is recorded")
}

Method TestOnlyTheCommunicatorsMayHandleAlerts()
{
	New $Namespace
	Set $Namespace = "%SYS"
	For tUser = "communicator1", "communicator2" {
		Do $$$AssertTrue((","_..RolesOf(tUser)_",")[",%EnsRole_AlertAdministrator,", tUser_" holds the platform's alert administrator role, so a matching read-back can close an alert owned by a colleague")
	}
	For tUser = "reviewer1", "observer" {
		Do $$$AssertNotTrue((","_..RolesOf(tUser)_",")[",%EnsRole_AlertAdministrator,", tUser_" does not")
	}
}

ClassMethod RolesOf(pUser As %String) As %String
{
	Set tUser = ##class(Security.Users).%OpenId(pUser)
	Quit:'$IsObject(tUser) ""
	Set tText = ""
	For i = 1:1:tUser.Roles.Count() { Set tText = tText_$Select(tText="":"", 1:",")_tUser.Roles.GetAt(i) }
	Quit tText
}

Method TestOnlyAlertsOfCriticalResultsAreOurs()
{
	Do $$$AssertTrue(##class(Readback.Notify.Raise).IsOurs(##class(Readback.Notify.Raise).TextFor("X", "2823-3", 3)), "the text this product raises is ours")
	Do $$$AssertNotTrue(##class(Readback.Notify.Raise).IsOurs("No task could be created for X"), "any other alert of the production is not")
}

}
