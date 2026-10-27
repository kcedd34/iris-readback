/// P-4: the repeated value must match before a communication is recorded. These tests drive the verification
/// the engine calls from OnAction; completion through the engine itself is covered by tests/e2e/readback_check.py.
Class Readback.Test.ReadbackTaskTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Trace.ReadbackAttempt WHERE TaskId LIKE 'T-UNIT-%')
	&sql(DELETE FROM Readback_Trace.Decision WHERE TaskId LIKE 'T-UNIT-%')
	&sql(DELETE FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'RT-UNIT-%')
}

/// A stored result with value 6.9 and a decision trace pointing at the task.
ClassMethod Case(pN As %Integer, pValue As %String = "6.9") As %String
{
	Set tControl = "RT-UNIT-"_pN, tTask = "T-UNIT-"_pN
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = tControl, tLab.PatientId = "SYN0000099", tLab.AnalyteCode = "2823-3"
	Set tLab.ValueText = pValue, tLab.Source = "file"
	Do tLab.%Save()
	Set tTrace = ##class(Readback.Trace.Decision).%New()
	Set tTrace.MessageControlId = tControl, tTrace.SessionId = pN, tTrace.TaskId = tTask
	Do tTrace.%Save()
	Quit tTask
}

ClassMethod Attempts(pTask As %String) As %Integer
{
	&sql(SELECT COUNT(*) INTO :n FROM Readback_Trace.ReadbackAttempt WHERE TaskId = :pTask)
	Quit n
}

ClassMethod Confirmed(pTask As %String) As %String
{
	&sql(SELECT TOP 1 ConfirmedBy INTO :c FROM Readback_Trace.Decision WHERE TaskId = :pTask)
	Quit $Get(c)
}

Method TestComparison()
{
	Set tMatch = ##class(Readback.Workflow.ReadbackTask).%ClassName(1)
	For tCase = $ListBuild("6.9", "6.9", 1), $ListBuild("6.9", "6.90", 1), $ListBuild("6.9", "  6.9  ", 1), $ListBuild("6.9", "9.6", 0), $ListBuild("6.9", "", 0), $ListBuild("6.9", "six", 0), $ListBuild("6.9", "6,9", 0), $ListBuild("6.9", "6.9 mmol/L", 0), $ListBuild("6.9", "69", 0), $ListBuild("6.9", "0.69", 0), $ListBuild("", "6.9", 0), $ListBuild("HEMOLYZED", "hemolyzed", 1), $ListBuild("HEMOLYZED", "other", 0) {
		Set tGot = ##class(Readback.Workflow.ReadbackTask).Matches($List(tCase, 1), $List(tCase, 2))
		Do $$$AssertEquals(tGot, $List(tCase, 3), "original '"_$List(tCase, 1)_"' against '"_$List(tCase, 2)_"'")
	}
}

Method TestMismatchIsBlockedAndKept()
{
	Set tTask = ..Case(1)
	Set tSC = ##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "Dr. Example", "9.6")
	Do $$$AssertStatusNotOK(tSC, "a divergent value is blocked")
	Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: "_##class(Readback.Workflow.ReadbackTask).#MismatchText, "with the text the person sees")
	Do $$$AssertEquals(..Attempts(tTask), 1, "the attempt is kept")
	Do $$$AssertEquals(..Confirmed(tTask), "", "nothing is confirmed in the trace")
}

Method TestThreeDivergentAttemptsThenAMatch()
{
	Set tTask = ..Case(2)
	For tValue = "9.6", "", "six" {
		Do $$$AssertStatusNotOK(##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "Dr. Example", tValue), "'"_tValue_"' is blocked")
	}
	Do $$$AssertEquals(..Attempts(tTask), 3, "all three attempts are kept")
	Do $$$AssertEquals(..Confirmed(tTask), "", "still nothing confirmed")
	Do $$$AssertStatusOK(##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "Dr. Example", "6.90"), "the matching value passes")
	Do $$$AssertEquals(..Attempts(tTask), 4, "the match is an attempt too")
	Do $$$AssertEquals(..Confirmed(tTask), "communicator1", "the trace records who confirmed")
	&sql(SELECT COUNT(*) INTO :m FROM Readback_Trace.ReadbackAttempt WHERE TaskId = :tTask AND Matched = 1)
	Do $$$AssertEquals(m, 1, "exactly one attempt matched")
	&sql(SELECT ReadbackMatch, ConfirmedAt INTO :tm, :tc FROM Readback_Trace.Decision WHERE TaskId = :tTask)
	Do $$$AssertEquals(tm, 1, "ReadbackMatch is set")
	Do $$$AssertTrue($Get(tc)'="", "ConfirmedAt is set")
}

Method TestWhoWasToldIsRequired()
{
	Set tTask = ..Case(3)
	Set tSC = ##class(Readback.Workflow.ReadbackTask).Verify(tTask, "communicator1", "", "6.9")
	Do $$$AssertStatusNotOK(tSC, "the right value without whom was told does not count")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["whom you told", "the person is told what is missing")
	Do $$$AssertEquals(..Confirmed(tTask), "", "nothing is confirmed")
}

Method TestOnlyCommunicatedCompletesTheTask()
{
	Set tTask = ##class(Readback.Workflow.ReadbackTask).%New()
	Do $$$AssertStatusNotOK(tTask.OnAction("Dismiss"), "another action is refused")
	Do $$$AssertStatusNotOK(tTask.OnAction("Reviewed"), "the review action is refused on a read-back task")
}

Method TestOriginalValueComesFromTheStoredResult()
{
	Set tTask = ..Case(4, "7.2")
	Do $$$AssertEquals(##class(Readback.Workflow.ReadbackTask).OriginalValue(tTask), "7.2", "the original is read from the stored result")
	Do $$$AssertEquals(##class(Readback.Workflow.ReadbackTask).OriginalValue("T-UNIT-none"), "", "an unknown task has no original")
	Do $$$AssertStatusNotOK(##class(Readback.Workflow.ReadbackTask).Verify("T-UNIT-none", "u", "x", "7.2"), "a task with no original never matches")
}

Method TestReviewTaskAcceptsOnlyReviewed()
{
	Set tTask = ##class(Readback.Workflow.ReviewTask).%New()
	Do $$$AssertStatusNotOK(tTask.OnAction("Communicated"), "a review task does not accept the read-back action")
}

}
