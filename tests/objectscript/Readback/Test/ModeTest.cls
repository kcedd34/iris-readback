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

Method TestRedactRemovesTheKeyFromText()
{
	Set ^||ReadbackTestKey = "test-key-value"
	Set tText = ##class(Readback.Config.Mode).Redact("API error: Incorrect API key provided: test-key-value. See docs.")
	Do $$$AssertTrue(tText'["test-key-value", "the key value is gone")
	Do $$$AssertTrue(tText["[key redacted]", "replaced by the marker")
	Do $$$AssertEquals(##class(Readback.Config.Mode).Redact("no secret here"), "no secret here", "text without the key is unchanged")
}

Method TestRedactWithNoKeyLeavesTextAlone()
{
	Set ^||ReadbackTestKey = ""
	Do $$$AssertEquals(##class(Readback.Config.Mode).Redact("anything"), "anything", "no key, nothing to redact")
}

Method TestRedactCoversEveryCredentialShape()
{
	Set ^||ReadbackTestKey = "test-key-value"
	Set tRedact = "##class(Readback.Config.Mode).Redact"
	// The configured key in the other forms a message can carry.
	For tForm = "test-key-value", $ZConvert("test-key-value", "O", "URL"), $System.Encryption.Base64Encode("test-key-value") {
		Do $$$AssertTrue(##class(Readback.Config.Mode).Redact("failed with "_tForm_" in the request")'[tForm, "form removed: "_$Extract(tForm, 1, 6))
	}
	// Whatever the provider echoes, masked, cut or in a header, even when it is not the configured key.
	For tText = "Incorrect API key provided: sk-proj-abcd****wxyz. You can find your key", "header Authorization: Bearer abc.def-123", "Authorization=Basic dXNlcjpwYXNzd29yZA==", "password: hunter2value", "api_key=zzz999", "token sk-abc123def456ghi" {
		Set tOut = ##class(Readback.Config.Mode).Redact(tText)
		Do $$$AssertTrue(tOut["[key redacted]", "marker present for: "_$Extract(tText, 1, 25))
		Do $$$AssertTrue((tOut'["abcd****"), "masked value gone")
		Do $$$AssertTrue((tOut'["hunter2value") && (tOut'["zzz999") && (tOut'["dXNlcjpwYXNz") && (tOut'["abc.def-123"), "no credential value survives")
	}
	Do $$$AssertEquals(##class(Readback.Config.Mode).Redact("timeout after 30 seconds, task sk is not a key"), "timeout after 30 seconds, task sk is not a key", "ordinary text is unchanged")
}

}
