Include Ensemble

/// The delivery channel: what it records for each way a delivery goes, the text it sends, and that a delivery never touches
/// the alert. The operation is built here with the adapter injected, so no production is needed.
Class Readback.Test.NotifyChannelTest Extends %UnitTest.TestCase
{

Parameter FIRST = 987000;

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
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Readback_Trace.Notification WHERE SessionId BETWEEN 987000 AND 987099")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Alerting.ManagedAlert WHERE SessionId BETWEEN 987000 AND 987099")
}

ClassMethod Alert(pSession As %Integer, pLevel As %Integer = 0) As Ens.Alerting.ManagedAlert
{
	Set tAlert = ##class(Ens.Alerting.ManagedAlert).%New()
	Set tAlert.AlertText = ##class(Readback.Notify.Raise).TextFor("RN-UNIT-"_pSession, "2823-3", 3)
	Set tAlert.SessionId = pSession, tAlert.EscalationLevel = pLevel, tAlert.IsOpen = 1, tAlert.CurrentOwner = "communicator1"
	Set tAlert.AlertTime = $$$timeUTC
	Do tAlert.%Save()
	Quit tAlert
}

ClassMethod Request(pAlert As Ens.Alerting.ManagedAlert, pPerson As %String, pType As %Integer = 0) As Ens.Alerting.NotificationRequest
{
	Set tReq = ##class(Ens.Alerting.NotificationRequest).%New()
	Set tReq.ManagedAlert = pAlert, tReq.NotificationType = pType
	Do tReq.AlertDestinations.Insert(pPerson)
	Quit tReq
}

ClassMethod Operation(pMode As %String) As Readback.Notify.Operation
{
	Set tOp = ##class(Readback.Notify.Operation).%New("Readback.Notify.Pager")
	Set tOp.Adapter = ##class(Readback.Notify.Pager).%New()
	Set tOp.Adapter.DeliveryMode = pMode
	Quit tOp
}

/// The events of a session, in order, as a comma list: "event:detail-start".
ClassMethod Events(pSession As %Integer) As %String
{
	Set tOut = ""
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Event, Detail FROM Readback_Trace.Notification WHERE SessionId = ? ORDER BY ID", pSession)
	While tRS.%Next() { Set tOut = tOut_$Select(tOut="":"", 1:",")_tRS.%Get("Event")_":"_$Piece(tRS.%Get("Detail"), " ", 1, 2) }
	Quit tOut
}

Method TestADeliveryThatIsAcknowledgedHasAReceipt()
{
	Set tAlert = ..Alert(987001)
	Set tSC = ..Operation("deliver").OnNotify(..Request(tAlert, "communicator1"), .tResp)
	Do $$$AssertStatusOK(tSC, "the operation answers success")
	Do $$$AssertTrue(..Events(987001) [ "delivery-attempt:sent through", "the attempt is recorded")
	Do $$$AssertTrue(..Events(987001) [ "delivery-receipt:receipt pager-", "and the receipt after it")
	Do $$$AssertNotTrue(..Events(987001) [ "delivery-failed", "no failure")
}

Method TestAnUnacknowledgedDeliveryIsNotAReceipt()
{
	Set tAlert = ..Alert(987002)
	Set tSC = ..Operation("silent").OnNotify(..Request(tAlert, "communicator1"), .tResp)
	Do $$$AssertStatusOK(tSC, "the engine is not told to retry")
	Do $$$AssertEquals(..Events(987002), "delivery-attempt:sent through,delivery-failed:not acknowledged", "an attempt, then a failure that says why")
}

Method TestAFailedDeliveryIsRecordedAndStillReturnsSuccess()
{
	Set tAlert = ..Alert(987003)
	Set tSC = ..Operation("fail").OnNotify(..Request(tAlert, "communicator1"), .tResp)
	Do $$$AssertStatusOK(tSC, "the operation still answers success, so the engine does not resend on its own")
	Do $$$AssertTrue(..Events(987003) [ "delivery-failed:channel error:", "the channel error is recorded")
	Do $$$AssertNotTrue(..Events(987003) [ "delivery-receipt", "and there is no receipt")
}

Method TestNoDeliveryChangesTheAlert()
{
	For tMode = "deliver", "silent", "fail" {
		Set tAlert = ..Alert(987010 + $Case(tMode, "deliver":0, "silent":1, :2), 1)
		Set tId = tAlert.%Id()
		Do ..Operation(tMode).OnNotify(..Request(tAlert, "communicator2"), .tResp)
		Set tAfter = ##class(Ens.Alerting.ManagedAlert).%OpenId(tId)
		Do $$$AssertEquals(tAfter.IsOpen, 1, "mode "_tMode_": the alert is still open")
		Do $$$AssertEquals(tAfter.EscalationLevel, 1, "mode "_tMode_": the level did not move")
		Do $$$AssertEquals(tAfter.Actions.Count(), 0, "mode "_tMode_": the platform's action list holds nothing from the delivery")
	}
}

Method TestTheTextHasTheCaseAndNoValueOrPatient()
{
	Set tAlert = ..Alert(987020)
	Set tOp = ..Operation("deliver")
	Set tFirst = tOp.TextFor(..Request(tAlert, "communicator1", 0), tAlert)
	Do $$$AssertTrue(tFirst [ "RN-UNIT-987020", "the case id is in the first text")
	Do $$$AssertTrue(tFirst [ "severity 3", "and the severity")
	Do $$$AssertNotTrue(tFirst [ "reminder", "the first text is not worded as a reminder")
	Do $$$AssertNotTrue(tFirst [ "SYN", "and names no patient")
	Set tEsc = tOp.TextFor(..Request(tAlert, "communicator2", $$$eAlertNotificationEscalationChange), tAlert)
	Do $$$AssertTrue(tEsc [ "Escalation Level of this alert has changed", "an escalation carries the platform's own line")
	Set tRem = tOp.TextFor(..Request(tAlert, "communicator2", $$$eAlertNotificationReminder), tAlert)
	Do $$$AssertTrue(tRem [ "reminder message", "a reminder carries the platform's own line")
	// The alert holds no value; look for the value with its unit, since a bare "6.9" can turn up inside a time stamp.
	Do $$$AssertNotTrue((tFirst_tEsc_tRem) [ "mmol", "no value in any text")
}

}
