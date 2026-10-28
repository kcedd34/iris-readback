/// The escalation configuration: validation, who is alerted at a level, the windows, and that a reload takes effect.
Class Readback.Test.EscalationTest Extends %UnitTest.TestCase
{

Parameter FILE = "/tmp/readback-escalation-test.json";

Method OnBeforeAllTests() As %Status
{
	Set ..%TestSaved = $Get(^Readback("escalation"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..%TestSaved '= "" { Set ^Readback("escalation") = ..%TestSaved } Else { Kill ^Readback("escalation") }
	Do ##class(%File).Delete(..#FILE)
	Quit $$$OK
}

Property %TestSaved As %String;

ClassMethod Write(pText As %String)
{
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(..#FILE)
	Do tStream.Write(pText)
	Do tStream.%Save()
}

ClassMethod Good(pFirst As %String = 30, pWindow As %String = 30) As %String
{
	Quit "{""firstWindowSeconds"":"_pFirst_",""windowSeconds"":"_pWindow_",""levels"":[{""recipient"":""communicator1""},{""recipient"":""communicator2""}]}"
}

Method TestAValidFileLoads()
{
	Do ##class(Readback.Notify.Escalation).Clear()
	Do ..Write(..Good())
	Do $$$AssertStatusOK(##class(Readback.Notify.Escalation).Load(..#FILE), "a valid file loads")
	Do $$$AssertTrue(##class(Readback.Notify.Escalation).IsLoaded(), "and is held")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).Levels(), 2, "two levels")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).FirstWindow(), 30, "first window")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).Window(), 30, "later windows")
}

Method TestTheShippedFileLoads()
{
	Do ##class(Readback.Notify.Escalation).Clear()
	Do $$$AssertStatusOK(##class(Readback.Notify.Escalation).Load(), "the file that ships with the product is valid")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(0), "communicator1", "the first person is the first communicator")
}

Method TestInvalidFilesLoadNothing()
{
	Set tBad = $ListBuild("{""firstWindowSeconds"":30,""windowSeconds"":30,""levels"":[]}", "{""firstWindowSeconds"":0,""windowSeconds"":30,""levels"":[{""recipient"":""a""}]}", "{""firstWindowSeconds"":30,""windowSeconds"":""soon"",""levels"":[{""recipient"":""a""}]}", "{""firstWindowSeconds"":30,""windowSeconds"":30,""levels"":[{""recipient"":""""}]}", "{""firstWindowSeconds"":30,""windowSeconds"":30}", "not json", "[1,2]", "{""firstWindowSeconds"":1.5,""windowSeconds"":30,""levels"":[{""recipient"":""a""}]}")
	Set tPtr = 0
	While $ListNext(tBad, tPtr, tText) {
		Do ##class(Readback.Notify.Escalation).Clear()
		Do ..Write(tText)
		Set tSC = ##class(Readback.Notify.Escalation).Load(..#FILE)
		Do $$$AssertStatusNotOK(tSC, "rejected: "_tText)
		Do $$$AssertNotTrue(##class(Readback.Notify.Escalation).IsLoaded(), "and nothing is loaded")
	}
	Do $$$AssertStatusNotOK(##class(Readback.Notify.Escalation).Load("/tmp/readback-no-such-file.json"), "a missing file is rejected")
}

Method TestAFailedReloadKeepsTheConfigurationInForce()
{
	Do ..Write(..Good())
	Do ##class(Readback.Notify.Escalation).Load(..#FILE)
	Do ..Write("not json")
	Do $$$AssertStatusNotOK(##class(Readback.Notify.Escalation).Load(..#FILE), "the bad file is rejected")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).Levels(), 2, "the earlier configuration is still in force")
}

Method TestWhoIsAlertedAtALevel()
{
	Do ..Write(..Good())
	Do ##class(Readback.Notify.Escalation).Load(..#FILE)
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(0), "communicator1", "level 0")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(1), "communicator2", "level 1")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(5), "communicator2", "a level beyond the list is the last person")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(""), "communicator1", "no level is the first person")
}

Method TestNextLevelStopsAtTheLastIndex()
{
	Do ..Write(..Good())
	Do ##class(Readback.Notify.Escalation).Load(..#FILE)
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).NextLevel(0), 1, "0 goes to 1")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).NextLevel(1), 1, "the last level stays")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).NextLevel(4), 1, "a level past the end comes back to the last")
	Do $$$AssertNotTrue(##class(Readback.Notify.Escalation).IsExhausted(0), "not exhausted at level 0")
	Do $$$AssertTrue(##class(Readback.Notify.Escalation).IsExhausted(1), "exhausted at the last level")
}

Method TestEditingAndReloadingChangesTheNextAnswer()
{
	Do ..Write(..Good(30, 30))
	Do ##class(Readback.Notify.Escalation).Load(..#FILE)
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).Window(), 30, "before the edit")
	Do ..Write("{""firstWindowSeconds"":5,""windowSeconds"":7,""levels"":[{""recipient"":""x""},{""recipient"":""y""},{""recipient"":""z""}]}")
	Do ##class(Readback.Notify.Escalation).Load(..#FILE)
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).FirstWindow(), 5, "the first window changed")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).Window(), 7, "the window changed")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).RecipientFor(2), "z", "a third person is reachable")
	Do $$$AssertEquals(##class(Readback.Notify.Escalation).NextLevel(1), 2, "and the list is three long")
}

}
