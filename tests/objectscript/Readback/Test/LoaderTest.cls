/// Loading and reloading the configuration tables.
Class Readback.Test.LoaderTest Extends %UnitTest.TestCase
{

Parameter DIR = "/tmp/readback-loadertest";

ClassMethod Write(pFile As %String, pText As %String)
{
	Set tDir = ##class(%File).GetDirectory(pFile)
	Do ##class(%File).CreateDirectoryChain(tDir)
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(pFile)
	Do tStream.Write(pText)
	Do tStream.%Save()
}

ClassMethod Prices(pPrice As %String = "null") As %String
{
	Quit "{""prices"":[{""model"":""m1"",""inputPerMillion"":"_pPrice_",""outputPerMillion"":"_pPrice_",""priceDate"":""2026-10-27""}]}"
}

ClassMethod Range(pExtra As %String = "") As %String
{
	Quit "{""analyteCode"":""2823-3"",""unit"":""mmol/L"",""ageGroup"":""adult"",""criticalLow"":2.5,""criticalHigh"":6.5,""floorSeverity"":3,""source"":""test table""}"
}

Method OnAfterAllTests() As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..#DIR)
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method TestValidLoadAndReload()
{
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_"]}")
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices("1.5"))
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR, .tCounts)
	Do $$$AssertStatusOK(tSC, "valid files load")
	Do $$$AssertEquals($Get(tCounts("ranges")), 1, "one range loaded")
	Do $$$AssertEquals($Get(tCounts("prices")), 1, "one price loaded")
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_","_$Replace(..Range(), "adult", "child")_"]}")
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR, .tCounts)
	Do $$$AssertEquals($Get(tCounts("ranges")), 2, "reload after an edit picks up the new row")
	&sql(SELECT COUNT(*) INTO :tN FROM Readback_Config.Range)
	Do $$$AssertEquals(tN, 2, "the table was replaced, not appended")
}

Method TestMalformedRowIsRejectedAndTableUnchanged()
{
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_"]}")
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices())
	Do ##class(Readback.Config.Loader).LoadAll(..#DIR)
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":[{""analyteCode"":""2823-3"",""ageGroup"":""adult"",""criticalHigh"":6.5,""floorSeverity"":3,""source"":""x""}]}")
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR)
	Do $$$AssertStatusNotOK(tSC, "a row without unit is rejected")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["unit", "the message names the missing field")
	&sql(SELECT COUNT(*) INTO :tN FROM Readback_Config.Range)
	Do $$$AssertEquals(tN, 1, "the previous table is kept after a rejected load")
}

Method TestInvalidValuesAreRejected()
{
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices())
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":[{""analyteCode"":""a"",""unit"":""u"",""ageGroup"":""senior"",""criticalHigh"":1,""floorSeverity"":3,""source"":""x""}]}")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "an unknown age group is rejected")
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":[{""analyteCode"":""a"",""unit"":""u"",""ageGroup"":""adult"",""floorSeverity"":3,""source"":""x""}]}")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "a row with neither limit is rejected")
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":[{""analyteCode"":""a"",""unit"":""u"",""ageGroup"":""adult"",""criticalHigh"":1,""floorSeverity"":4,""source"":""x""}]}")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "a floor severity above 3 is rejected")
	Do ..Write(..#DIR_"/config/critical-ranges.json", "not json")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "text that is not JSON is rejected")
}

}
