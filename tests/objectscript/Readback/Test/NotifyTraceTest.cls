/// The notification trace: values it accepts, redaction, and the join to the decision by session.
Class Readback.Test.NotifyTraceTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Kill ^||ReadbackTestKey
	Quit $$$OK
}

ClassMethod Clean()
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Readback_Trace.Notification WHERE SessionId BETWEEN 987200 AND 987299")
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'RT-UNIT-NT%')
}

Method TestEveryEventOfTheListIsAccepted()
{
	For tEvent = "opened", "delivery-attempt", "delivery-receipt", "delivery-failed", "escalated", "exhausted", "confirmed" {
		Do $$$AssertStatusOK(##class(Readback.Trace.Notification).Add(987201, 1, tEvent, "p", 0, "d"), tEvent_" is accepted")
	}
}

Method TestAnotherEventIsRefused()
{
	Do $$$AssertStatusNotOK(##class(Readback.Trace.Notification).Add(987202, 1, "closed-by-delivery", "p", 0, "d"), "an event outside the list is refused")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Readback_Trace.Notification WHERE SessionId = 987202")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.%GetData(1), 0, "and nothing is stored")
}

Method TestADetailOver300CharactersIsRefusedByTheClassAndTruncatedByAdd()
{
	Set tRow = ##class(Readback.Trace.Notification).%New()
	Set tRow.SessionId = 987203, tRow.Event = "opened", tRow.Detail = $Translate($Justify("", 301), " ", "x")
	Do $$$AssertStatusNotOK(tRow.%Save(), "301 characters do not fit the field")
	Do ##class(Readback.Trace.Notification).Add(987203, 1, "opened", "p", 0, $Translate($Justify("", 400), " ", "y"))
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT LENGTH(Detail) AS N FROM Readback_Trace.Notification WHERE SessionId = 987203")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.%Get("N"), 300, "Add keeps the first 300 characters")
}

Method TestACredentialInTheDetailIsStoredRedacted()
{
	Set ^||ReadbackTestKey = "key-for-the-notify-test-0123456789"
	Do ##class(Readback.Trace.Notification).Add(987204, 1, "delivery-failed", "p", 0, "channel error: Bearer abcdef0123456789 and key-for-the-notify-test-0123456789")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Detail FROM Readback_Trace.Notification WHERE SessionId = 987204")
	Do tRS.%Next()
	Set tDetail = tRS.%Get("Detail")
	Do $$$AssertNotTrue(tDetail [ "key-for-the-notify-test", "the key is not stored")
	Do $$$AssertNotTrue(tDetail [ "abcdef0123456789", "a bearer value is not stored")
	Do $$$AssertTrue(tDetail [ "[key redacted]", "the mark is")
	Kill ^||ReadbackTestKey
}

Method TestRowsJoinToTheDecisionBySession()
{
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = "RT-UNIT-NT1", tTrace.SessionId = 987205
	Do tTrace.%Save()
	Do ##class(Readback.Trace.Notification).Add(987205, 7, "opened", "communicator1", 0, "alert opened")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT d.MessageControlId AS Id, n.Event AS Event FROM Readback_Trace.Decision d JOIN Readback_Trace.Notification n ON n.SessionId = d.SessionId WHERE d.MessageControlId = 'RT-UNIT-NT1'")
	Do tRS.%Next()
	Do $$$AssertEquals(tRS.%Get("Event"), "opened", "the row is found from the decision")
}

}
