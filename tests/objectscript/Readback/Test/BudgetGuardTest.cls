/// P-7: the budget guard. Trace rows are inserted with set CreatedAt values to check the sliding window.
Class Readback.Test.BudgetGuardTest Extends %UnitTest.TestCase
{

Parameter DIR = "/tmp/readback-guardtest";

Method OnBeforeAllTests() As %Status
{
	Quit ..Reset()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Do ##class(%File).RemoveDirectoryTree(..#DIR)
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Reset() As %Status
{
	Do ..Clean()
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'BGT-%')
}

/// What the window already holds from real trace rows of the last hour: tests work relative to it.
ClassMethod Base(pModel As %String = "none", Output pCost As %Numeric) As %Integer
{
	Set tState = ##class(Readback.Budget.State).%New()
	Do ##class(Readback.Budget.Guard).Window(pModel, ##class(Readback.Config.Budget).Current(), tState)
	Set pCost = $Select(tState.Basis="cost":tState.Used, 1:0)
	Quit $Select(tState.Basis="tokens":tState.Used, 1:0)
}

ClassMethod SetBudget(pPerResult As %Integer, pCost As %Numeric, pTokens As %Integer)
{
	Do ##class(Readback.Test.LoaderTest).Write(..#DIR_"/b.json", "{""perResultTokens"":"_pPerResult_",""hourlyCostUsd"":"_pCost_",""hourlyTokens"":"_pTokens_"}")
	Do ##class(Readback.Config.Loader).LoadBudget(..#DIR_"/b.json")
}

/// A trace row of an agent call (or not) pMinutes ago.
ClassMethod Row(pMinutes As %Integer, pTokensIn As %Integer, pTokensOut As %Integer, pCalled As %Boolean = 1, pCost As %Numeric = "", pModel As %String = "m")
{
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = "BGT-"_$Increment(^||bgt), tRow.SessionId = 1, tRow.AgentCalled = pCalled
	Set tRow.InputTokens = pTokensIn, tRow.OutputTokens = pTokensOut, tRow.Model = pModel
	If pCost '= "" { Set tRow.CostUsd = pCost, tRow.CostKnown = 1 }
	Set tNow = $ZTimeStamp, tDay = $Piece(tNow, ",", 1), tSec = $Piece(tNow, ",", 2) - (pMinutes * 60)
	While tSec < 0 { Set tSec = tSec + 86400, tDay = tDay - 1 }
	Set tRow.CreatedAt = $ZDateTime(tDay_","_tSec, 3, 1, 3)
	Set tSC = tRow.%Save()
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.StatusException).CreateFromStatus(tSC) }
}

ClassMethod SetRounds(pRounds As %Integer)
{
	Do ##class(Readback.Test.LoaderTest).Write(..#DIR_"/a.json", "{""maxIterations"":6,""maxToolCalls"":6,""toolResultMaxChars"":2000,""expectedRounds"":"_pRounds_"}")
	Do ##class(Readback.Config.Loader).LoadAgentTools(..#DIR_"/a.json")
}

Method TestEstimateIsCharsOverFourRoundedUp()
{
	Do $$$AssertEquals(##class(Readback.Budget.Guard).EstimateTokens(400), 100, "400 characters are 100 tokens")
	Do $$$AssertEquals(##class(Readback.Budget.Guard).EstimateTokens(401), 101, "401 characters round up to 101")
	Do $$$AssertEquals(##class(Readback.Budget.Guard).EstimateTokens(0), 0, "nothing is 0")
}

Method TestEstimateCountsEveryRound()
{
	Do ..SetBudget(1000000, 5, 2000000)
	Set tBase = ##class(Readback.Budget.Guard).EstimateTokens($Length(##class(Readback.Triage.Prompt).Text()) + 401) + ##class(Readback.Budget.Guard).#ToolDefinitionTokens
	Do ..SetRounds(1)
	Set tOne = ##class(Readback.Budget.Guard).Check($Justify("", 401)).EstimatedTokens
	Do $$$AssertEquals(tOne, tBase + ##class(Readback.Triage.Schema).#MaxTokens, "one round: one request and the longest answer")
	Do ..SetRounds(3)
	Set tThree = ##class(Readback.Budget.Guard).Check($Justify("", 401)).EstimatedTokens
	Do $$$AssertTrue(tThree > 3 * tBase, "three rounds send the conversation three times and add the tool results")
	Do $$$AssertTrue(tThree > tOne, "the estimate grows with the rounds")
	Do ..SetRounds(6)
	Do $$$AssertTrue(##class(Readback.Budget.Guard).Check($Justify("", 401)).EstimatedTokens > tThree, "and keeps growing")
	Do ..SetRounds(3)
}

Method TestResultCeilingRefusesAnInvestigationThatCannotFit()
{
	Do ..SetRounds(3)
	Do ..SetBudget(1000000, 5, 2000000)
	Set tNeeds = ##class(Readback.Budget.Guard).Check("short").EstimatedTokens
	Do ..SetBudget(tNeeds, 5, 2000000)
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Check("short").State, "ok", "exactly at the ceiling fits")
	Do ..SetBudget(tNeeds - 1, 5, 2000000)
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Check("short").State, "result-ceiling", "one token over is the result ceiling")
}

Method TestNoAgentBoundsMeansNoCall()
{
	Do ##class(Readback.Config.AgentTools).%KillExtent()
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Check("short").State, "result-ceiling", "without the agent bounds no call is made")
	Do ..SetRounds(3)
}

Method TestHourlyTokensWhenPriceUnknown()
{
	Do ..Clean()
	Do ..SetBudget(100000, 5, 1000)
	Set tBase = ..Base()
	Do ..SetBudget(100000, 5, tBase + 1000)
	Do ..Row(5, 300, 100)
	Set tState = ##class(Readback.Budget.Guard).Check("short", "no-such-model")
	Do $$$AssertEquals(tState.Basis, "tokens", "no price means the token basis")
	Do $$$AssertEquals(tState.Used, tBase + 400, "input plus output tokens are summed")
	Do $$$AssertEquals(tState.Ceiling, tBase + 1000, "against the token ceiling")
	Do $$$AssertEquals(tState.State, "ok", "below the ceiling is ok")
	Do ..Row(10, 500, 99)
	Set tState = ##class(Readback.Budget.Guard).Check("short", "no-such-model")
	Do $$$AssertEquals(tState.State, "ok", "999 of 1000 is still ok")
	Do ..Row(1, 1, 0)
	Set tState = ##class(Readback.Budget.Guard).Check("short", "no-such-model")
	Do $$$AssertEquals(tState.State, "hourly-ceiling", "exactly at the ceiling is the ceiling")
}

Method TestWindowIgnoresOldRowsAndCallsThatDidNotHappen()
{
	Do ..Clean()
	Do ..SetBudget(100000, 5, 1000)
	Set tBase = ..Base()
	Do ..Row(61, 900, 900)
	Do ..Row(59, 100, 100, 0)
	Set tState = ##class(Readback.Budget.Guard).Check("short", "no-such-model")
	Do $$$AssertEquals(tState.Used, tBase, "a row older than 60 minutes and a row with no agent call are not counted")
	Do ..Row(59, 100, 100)
	Set tState = ##class(Readback.Budget.Guard).Check("short", "no-such-model")
	Do $$$AssertEquals(tState.Used, tBase + 200, "a row 59 minutes old is counted")
}

Method TestCostBasisWhenPriceKnown()
{
	Do ..Clean()
	Set tPrice = ##class(Readback.Config.Price).%New()
	Set tPrice.Model = "bgt-priced", tPrice.InputPerMillion = 1, tPrice.OutputPerMillion = 2, tPrice.PriceDate = +$Horolog
	Do $$$AssertStatusOK(tPrice.%Save(), "the test price is stored")
	Do ..SetBudget(100000, 5, 10)
	Do ..Base("bgt-priced", .tBaseCost)
	Do ..SetBudget(100000, tBaseCost + 0.5, 10)
	Do ..Row(3, 1000000, 0, 1, 0.3, "bgt-priced")
	Do ..Row(4, 5000000, 5000000, 1, "", "bgt-priced")
	Set tState = ##class(Readback.Budget.Guard).Check("short", "bgt-priced")
	Do $$$AssertEquals(tState.Basis, "cost", "a known price means the cost basis")
	Do $$$AssertEquals(tState.Used, tBaseCost + 0.3, "only known costs are summed")
	Do $$$AssertEquals(tState.State, "ok", "0.3 of 0.5 is ok even though the token ceiling of 10 is far exceeded")
	Do ..Row(2, 1, 1, 1, 0.2, "bgt-priced")
	Set tState = ##class(Readback.Budget.Guard).Check("short", "bgt-priced")
	Do $$$AssertEquals(tState.State, "hourly-ceiling", "0.5 of 0.5 is the ceiling")
	Do tPrice.%DeleteId(tPrice.%Id())
}

Method TestChangedCeilingAppliesAfterReload()
{
	Do ..Clean()
	Do ..SetBudget(100000, 5, 100)
	Set tBase = ..Base()
	Do ..SetBudget(100000, 5, tBase + 100)
	Do ..Row(1, 80, 80)
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Check("x", "none").State, "hourly-ceiling", "over a low ceiling")
	Do ..SetBudget(100000, 5, tBase + 100000)
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Check("x", "none").State, "ok", "a higher ceiling applies at the next check")
}

Method TestNowForTheStatusEndpoint()
{
	Do ..Clean()
	Do ..SetBudget(7000, 5, 100)
	Set tBase = ..Base()
	Do ..SetBudget(7000, 5, tBase + 100)
	Set tNow = ##class(Readback.Budget.Guard).Now("none")
	Do $$$AssertEquals(tNow.state, "ok", "ok with room in the window")
	Do $$$AssertEquals(tNow.perResultTokens, 7000, "the per result ceiling is shown")
	Do ..Row(1, 100, 100)
	Do $$$AssertEquals(##class(Readback.Budget.Guard).Now("none").state, "reached", "reached when the window is full")
}

}
