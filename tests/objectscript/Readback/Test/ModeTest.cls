/// Run mode depends only on whether a non-empty provider key is configured.
Class Readback.Test.ModeTest Extends %UnitTest.TestCase
{

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||ReadbackTestKey
	Quit $$$OK
}

Method TestAbsentIsReplay()
{
	Kill ^||ReadbackTestKey
	If $System.Util.GetEnviron("OPENAI_API_KEY") = "" {
		Do $$$AssertEquals(##class(Readback.Config.Mode).Current(), "replay", "no key in the environment means replay")
	} Else {
		Do $$$LogMessage("environment has a key; absent case covered by the empty case")
	}
}

Method TestEmptyIsReplay()
{
	Set ^||ReadbackTestKey = ""
	Do $$$AssertEquals(##class(Readback.Config.Mode).Current(), "replay", "empty key means replay")
}

Method TestWhitespaceIsReplay()
{
	Set ^||ReadbackTestKey = "   "
	Do $$$AssertEquals(##class(Readback.Config.Mode).Current(), "replay", "whitespace-only key means replay")
	Set ^||ReadbackTestKey = $Char(9)_" "_$Char(9)
	Do $$$AssertEquals(##class(Readback.Config.Mode).Current(), "replay", "tabs and spaces mean replay")
}

Method TestKeyIsLive()
{
	Set ^||ReadbackTestKey = "test-key-value"
	Do $$$AssertEquals(##class(Readback.Config.Mode).Current(), "live", "a configured key means live")
}

Method TestModeNeverReturnsTheKey()
{
	Set ^||ReadbackTestKey = "test-key-value"
	Do $$$AssertTrue(##class(Readback.Config.Mode).Current()'["test-key-value", "the mode text does not contain the key")
}

}
