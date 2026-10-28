/// Loading the budget ceilings: positive numbers only, the previous values stay on a rejected load.
Class Readback.Test.BudgetConfigTest Extends %UnitTest.TestCase
{

Parameter DIR = "/tmp/readback-budgettest";

Method OnAfterAllTests() As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..#DIR)
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Load(pText As %String, Output pSC As %Status) As %Status
{
	Do ##class(Readback.Test.LoaderTest).Write(..#DIR_"/budget.json", pText)
	Set pSC = ##class(Readback.Config.Loader).LoadBudget(..#DIR_"/budget.json", .tN)
	Quit pSC
}

Method TestValidLoad()
{
	Set tSC = ..Load("{""perResultTokens"":1234,""hourlyCostUsd"":2.5,""hourlyTokens"":99000}")
	Do $$$AssertStatusOK(tSC, "a valid file loads")
	Set tB = ##class(Readback.Config.Budget).Current()
	Do $$$AssertEquals(tB.PerResultTokens, 1234, "per result ceiling loaded")
	Do $$$AssertEquals(tB.HourlyCostUsd, 2.5, "hourly cost ceiling loaded")
	Do $$$AssertEquals(tB.HourlyTokens, 99000, "hourly token ceiling loaded")
}

Method TestReloadAppliesTheNewValue()
{
	Do ..Load("{""perResultTokens"":100,""hourlyCostUsd"":1,""hourlyTokens"":100}")
	Do ..Load("{""perResultTokens"":200,""hourlyCostUsd"":2,""hourlyTokens"":200}")
	Do $$$AssertEquals(##class(Readback.Config.Budget).Current().PerResultTokens, 200, "the next read sees the new value")
	&sql(SELECT COUNT(*) INTO :n FROM Readback_Config.Budget)
	Do $$$AssertEquals(n, 1, "there is exactly one row")
}

Method TestRejectedValuesKeepThePreviousOnes()
{
	Do ..Load("{""perResultTokens"":321,""hourlyCostUsd"":3,""hourlyTokens"":654}")
	For tText = "{""perResultTokens"":0,""hourlyCostUsd"":3,""hourlyTokens"":654}", "{""perResultTokens"":-5,""hourlyCostUsd"":3,""hourlyTokens"":654}", "{""perResultTokens"":""6000"",""hourlyCostUsd"":3,""hourlyTokens"":654}", "{""perResultTokens"":10,""hourlyCostUsd"":0,""hourlyTokens"":654}", "{""perResultTokens"":10,""hourlyCostUsd"":3}", "{""perResultTokens"":10.5,""hourlyCostUsd"":3,""hourlyTokens"":654}", "{""perResultTokens"":10,""hourlyCostUsd"":3,""hourlyTokens"":-1}", "not json" {
		Set tSC = ..Load(tText)
		Do $$$AssertStatusNotOK(tSC, "rejected: "_$Extract(tText, 1, 60))
	}
	Do $$$AssertEquals(##class(Readback.Config.Budget).Current().PerResultTokens, 321, "the previous values stay after every rejected load")
}

Method TestMessageNamesTheField()
{
	Set tSC = ..Load("{""perResultTokens"":0,""hourlyCostUsd"":3,""hourlyTokens"":654}")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["perResultTokens", "the message names the field")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["greater than 0", "and the rule")
}

Method TestShippedFileIsValid()
{
	Set tSC = ##class(Readback.Config.Loader).LoadBudget("/opt/readback/data/config/budget.json", .tN)
	Do $$$AssertStatusOK(tSC, "the shipped budget file loads")
	Do $$$AssertTrue(##class(Readback.Config.Budget).Current().PerResultTokens > 0, "with positive values")
}

}
