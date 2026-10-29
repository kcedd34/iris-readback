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

/// The analyte and budget files every load needs, valid by default.
ClassMethod WriteBase(pBudget As %String = "{""perResultTokens"":6000,""hourlyCostUsd"":5.0,""hourlyTokens"":2000000}")
{
	Do ..Write(..#DIR_"/config/analytes.json", "{""analytes"":[{""analyteCode"":""2823-3"",""name"":""Potassium"",""referenceUnit"":""mmol/L""},{""analyteCode"":""2345-7"",""name"":""Glucose"",""referenceUnit"":""mmol/L"",""molarMass"":180.156}]}")
	Do ..Write(..#DIR_"/config/budget.json", pBudget)
	Do ..Write(..#DIR_"/config/delta-rules.json", "{""rules"":[{""analyteCode"":""2823-3"",""unit"":""mmol/L"",""maxChange"":1.5,""windowHours"":24,""direction"":""either"",""floorSeverity"":3,""source"":""test table""}]}")
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
	Do ..WriteBase()
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_"]}")
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices("1.5"))
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR, .tCounts)
	Do $$$AssertStatusOK(tSC, "valid files load")
	Do $$$AssertEquals($Get(tCounts("ranges")), 1, "one range loaded")
	Do $$$AssertEquals($Get(tCounts("prices")), 1, "one price loaded")
	Do $$$AssertEquals($Get(tCounts("deltaRules")), 1, "one change rule loaded")
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_","_$Replace(..Range(), "adult", "child")_"]}")
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR, .tCounts)
	Do $$$AssertEquals($Get(tCounts("ranges")), 2, "reload after an edit picks up the new row")
	&sql(SELECT COUNT(*) INTO :tN FROM Readback_Config.Range)
	Do $$$AssertEquals(tN, 2, "the table was replaced, not appended")
}

Method TestMalformedRowIsRejectedAndTableUnchanged()
{
	Do ..WriteBase()
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
	Do ..WriteBase()
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

Method TestRangeUnitMustMatchTheReferenceUnit()
{
	Do ..WriteBase()
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices())
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_$Replace(..Range(), "mmol/L", "mg/dL")_"]}")
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR)
	Do $$$AssertStatusNotOK(tSC, "a range in another unit than the reference unit is rejected")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["reference unit", "the message names the reference unit")
}

Method TestAnalyteValidation()
{
	Do ..Write(..#DIR_"/config/critical-ranges.json", "{""ranges"":["_..Range()_"]}")
	Do ..Write(..#DIR_"/config/price-table.json", ..Prices())
	Do ..Write(..#DIR_"/config/budget.json", "{""perResultTokens"":1,""hourlyCostUsd"":1,""hourlyTokens"":1}")
	Do ..Write(..#DIR_"/config/analytes.json", "{""analytes"":[{""analyteCode"":""2345-7"",""name"":""Glucose"",""referenceUnit"":""mmol/L"",""molarMass"":0}]}")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "a molar mass of 0 is rejected")
	Do ..Write(..#DIR_"/config/analytes.json", "{""analytes"":[{""analyteCode"":""2345-7"",""name"":""Glucose"",""referenceUnit"":""mmol/L"",""molarMass"":""heavy""}]}")
	Do $$$AssertStatusNotOK(##class(Readback.Config.Loader).LoadAll(..#DIR), "a text molar mass is rejected")
	Do ..Write(..#DIR_"/config/analytes.json", "{""analytes"":[{""analyteCode"":""2345-7"",""name"":""Glucose""}]}")
	Set tSC = ##class(Readback.Config.Loader).LoadAll(..#DIR)
	Do $$$AssertStatusNotOK(tSC, "an analyte without a reference unit is rejected")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["referenceUnit", "the message names the field")
}

}
