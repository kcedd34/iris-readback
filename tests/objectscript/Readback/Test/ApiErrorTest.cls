/// Error bodies of /readback/api: always {"error":"..."}, redacted, no stack, no request data.
Class Readback.Test.ApiErrorTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Set ^||ReadbackTestKey = "test-key-value-123"
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^||ReadbackTestKey
	Quit $$$OK
}

/// The body written by the framework hook for a status, as a dynamic object.
ClassMethod Body(pStatus As %String, pSC As %Status) As %DynamicObject
{
	Set tBody = ##class(Readback.API.Status).ErrorBody(pStatus, $Select($System.Status.IsError(pSC):$System.Status.GetErrorText(pSC), 1:""))
	Quit {}.%FromJSON(tBody)
}

Method TestEveryErrorBodyIsOneErrorFieldOnly()
{
	For tStatus = "400 Bad Request", "403 Forbidden", "404 Not Found", "405 Method Not Allowed", "500 Internal Server Error" {
		Set tBody = ..Body(tStatus, $$$OK)
		Do $$$AssertEquals(tBody.%Size(), 1, tStatus_": one field")
		Do $$$AssertTrue(tBody.%IsDefined("error") && (tBody.error '= ""), tStatus_": the field is error and holds text")
	}
}

Method TestA500NeverRepeatsTheFailureTextAndNeverHoldsTheKey()
{
	Set tSC = $System.Status.Error(5001, "<UNDEFINED>zGetDecision+3^Readback.API.Status.1 secret test-key-value-123 in Authorization: Bearer test-key-value-123")
	Set tBody = ..Body("500 Internal Server Error", tSC)
	Do $$$AssertEquals(tBody.error, "internal error", "a 500 says only internal error")
	Do $$$AssertTrue(tBody.%ToJSON()'["test-key-value-123", "no key value")
	Do $$$AssertTrue(tBody.%ToJSON()'["Readback.API", "no routine name or stack")
}

Method TestA400OrA404TextIsRedacted()
{
	Set tBody = {}.%FromJSON(##class(Readback.API.Status).ErrorBody("400 Bad Request", "bad value test-key-value-123 and sk-abcdef123456"))
	Do $$$AssertTrue(tBody.error["[key redacted]", "the key is replaced")
	Do $$$AssertTrue(tBody.error'["test-key-value-123", "the configured key is gone")
	Do $$$AssertTrue(tBody.error'["sk-abcdef", "a key-shaped token is gone")
	Set tBody = {}.%FromJSON(##class(Readback.API.Status).ErrorBody("404 Not Found", "no decision recorded for that case id"))
	Do $$$AssertEquals(tBody.error, "no decision recorded for that case id", "a plain text is unchanged")
}

Method TestIndicatorsRefuseABadTimestamp()
{
	Do $$$AssertTrue('##class(Readback.Trace.Indicators).Valid("not a time"), "the route answers 400 for this value")
}

}
