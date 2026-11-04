/// The wait for the Java gateway: it tries again until the probe says ready, and when time runs out it says what it waited for and how many
/// attempts it made.
Class Readback.Test.UnitsGatewayTest Extends %UnitTest.TestCase
{

/// A probe that is ready from the third call on.
ClassMethod ReadyAtThird() As %Boolean
{
	Set ^||Calls = $Get(^||Calls) + 1
	Quit ^||Calls >= 3
}

ClassMethod Never() As %Boolean
{
	Quit 0
}

ClassMethod Throws() As %Boolean
{
	Throw ##class(%Exception.General).%New("probe", 5001, , "boom")
}

Method TestItTriesAgainUntilTheProbeIsReady()
{
	Kill ^||Calls
	Set tSC = ##class(Readback.Units.Setup).WaitUntil("ReadyAtThird", 30, 1, "the thing", .tAttempts, $ClassName())
	Do $$$AssertStatusOK(tSC, "the wait ends well once the probe is ready")
	Do $$$AssertEquals(tAttempts, 3, "it made three attempts")
}

Method TestItFailsWithAClearMessageWhenTimeRunsOut()
{
	Set tSC = ##class(Readback.Units.Setup).WaitUntil("Never", 3, 1, "the Java gateway", .tAttempts, $ClassName())
	Do $$$AssertStatusNotOK(tSC, "the wait fails when the probe is never ready")
	Set tText = $System.Status.GetErrorText(tSC)
	Do $$$AssertTrue(tText [ "the Java gateway did not become ready within 3 seconds", "the message names what it waited for and how long: "_tText)
	Do $$$AssertTrue(tAttempts >= 2, "it tried more than once ("_tAttempts_")")
}

Method TestAProbeThatThrowsCountsAsNotReady()
{
	Set tSC = ##class(Readback.Units.Setup).WaitUntil("Throws", 2, 1, "the probe", .tAttempts, $ClassName())
	Do $$$AssertStatusNotOK(tSC, "an error in the probe is not ready, and does not escape")
}

Method TestNothingListeningIsNotAGateway()
{
	Do $$$AssertEquals(##class(Readback.Units.Setup).Accepts("127.0.0.1", 59999, 2), 0, "a port with nothing behind it does not accept")
}

}
