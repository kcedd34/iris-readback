/// The controls of an evaluation run: the clean-state check, the ceilings and the replay set. The model and output cap
/// changes restart the agent item and are exercised by the live check; here only their input checks are tested.
Class Readback.Test.EvalControlTest Extends %UnitTest.TestCase
{

Method TestIsCleanNeedsNoTraceRows()
{
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = "EVC-1", tRow.SessionId = 1
	Do tRow.%Save()
	Do $$$AssertNotTrue(##class(Readback.Eval.Control).IsClean(.tWhy), "a trace row makes the state not clean")
	Do $$$AssertTrue(tWhy [ "trace rows exist", "and says why: "_tWhy)
	Do tRow.%DeleteId(tRow.%Id())
	// With every trace row gone, and the confirmed-case pool empty, the state is clean. Both deletions are rolled back.
	TStart
	&sql(DELETE FROM Readback_Trace.Decision)
	Set tDecisionOk = (SQLCODE >= 0)
	Set tPool = ##class(Readback.Retrieval.Engine).Snapshot().confirmedCases
	Set tClean = ##class(Readback.Eval.Control).IsClean(.tWhy2)
	TRollback
	Do $$$AssertTrue(tDecisionOk, "the trace rows could be removed inside the transaction")
	If tPool = 0 {
		Do $$$AssertTrue(tClean, "no trace row and an empty pool is clean: "_tWhy2)
	} Else {
		Do $$$AssertNotTrue(tClean, "a pool with "_tPool_" confirmed cases is not clean")
		Do $$$AssertTrue(tWhy2 [ "confirmed cases", "and says so: "_tWhy2)
	}
}

Method TestCeilingsWrittenAndRestored()
{
	Set tBefore = ##class(Readback.Config.Budget).Current()
	Set tTokens = tBefore.PerResultTokens, tCost = tBefore.HourlyCostUsd, tHour = tBefore.HourlyTokens
	Do $$$AssertStatusOK(##class(Readback.Eval.Control).UseCeilings(123456, 99, 987654321, .tPrevious), "the ceilings are written")
	Do $$$AssertEquals(##class(Readback.Config.Budget).Current().PerResultTokens, 123456, "the per-result ceiling changed")
	Do $$$AssertEquals(tPrevious.perResultTokens, tTokens, "the previous per-result value is returned")
	Do $$$AssertEquals(tPrevious.hourlyTokens, tHour, "the previous hourly token value is returned")
	Do $$$AssertTrue(##class(Readback.Eval.Control).CeilingsText() [ "123456", "the header text shows the ceilings in force")
	Do $$$AssertStatusOK(##class(Readback.Eval.Control).RestoreCeilings(tPrevious), "the ceilings are restored")
	Set tAfter = ##class(Readback.Config.Budget).Current()
	Do $$$AssertEquals(tAfter.PerResultTokens, tTokens, "the per-result ceiling is back")
	Do $$$AssertEquals(+tAfter.HourlyCostUsd, +tCost, "the hourly cost ceiling is back")
	Do $$$AssertEquals(tAfter.HourlyTokens, tHour, "the hourly token ceiling is back")
}

Method TestReplaySetCanBeSelected()
{
	Set tActive = ##class(Readback.Replay.Recording).ActiveSet()
	Do $$$AssertStatusOK(##class(Readback.Eval.Control).UseReplaySet("unit-evc"), "a set is selected")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).ActiveSet(), "unit-evc", "it is the active set")
	Do $$$AssertStatusNotOK(##class(Readback.Eval.Control).UseReplaySet(""), "an empty name is refused")
	Do ##class(Readback.Replay.Recording).Activate(tActive)
}

Method TestRestartingBadInput()
{
	Do $$$AssertStatusNotOK(##class(Readback.Eval.Control).UseModel(""), "an empty model name is refused before anything changes")
	For tBad = 0, -5, 1.5, "many" {
		Do $$$AssertStatusNotOK(##class(Readback.Eval.Control).UseOutputCap(tBad), "an output cap of "_tBad_" is refused")
	}
}

}
