/// Response class of the read-back task. The engine calls OnAction before it completes the task, so a
/// repeated value that does not match the original blocks completion for any client (P-4).
Class Readback.Workflow.ReadbackTask Extends EnsLib.Workflow.TaskResponse
{

Parameter MismatchText = "Read-back mismatch: the repeated value does not match the original. Enter the value again.";

Method OnAction(pAction As %String) As %Status
{
	If pAction '= "Communicated" {
		Quit $System.Status.Error(5001, "Only the action Communicated completes a read-back task.")
	}
	Set tUser = $Select($IsObject(..%TaskStatus):..%TaskStatus.AssignedTo, 1:"")
	Set tSC = ..Verify(..%Id(), tUser, ..%FormValues.GetAt("ToldWho"), ..%FormValues.GetAt("ReadbackValue"))
	Quit:$System.Status.IsError(tSC) tSC
	Quit ##super(pAction)
}

/// Checks one submission: records the attempt, and on a match records the confirmation in the trace.
/// Returns an error status, with the text the person sees, when the submission does not count.
ClassMethod Verify(pTaskId As %String, pUser As %String, pToldWho As %String, pRepeated As %String) As %Status
{
	Set tOriginal = ..OriginalValue(pTaskId)
	Set tToldWho = $ZStrip(pToldWho, "<>WC")
	Set tMatched = ..Matches(tOriginal, pRepeated) && (tToldWho '= "")
	Set tAttempt = ##class(Readback.Trace.ReadbackAttempt).%New()
	Set tAttempt.TaskId = pTaskId, tAttempt.UserName = pUser, tAttempt.ToldWho = tToldWho
	Set tAttempt.RepeatedValue = pRepeated, tAttempt.Matched = tMatched
	&sql(SELECT COUNT(*) INTO :tN FROM Readback_Trace.ReadbackAttempt WHERE TaskId = :pTaskId)
	Set tAttempt.AttemptNumber = tN + 1
	Do tAttempt.%Save()
	If tMatched {
		Do ..Confirm(pTaskId, pUser)
		Quit $$$OK
	}
	If tToldWho = "" { Quit $System.Status.Error(5001, "Enter whom you told, and the value you repeated back.") }
	Quit $System.Status.Error(5001, ..#MismatchText)
}

/// True when the repeated value is the original value. Numbers compare numerically after trimming, so 6.90
/// matches 6.9; anything that is not a plain number (another decimal separator, a unit) does not match a number.
/// A non-numeric original is compared as text, ignoring case.
ClassMethod Matches(pOriginal As %String, pRepeated As %String) As %Boolean
{
	Set tOriginal = $ZStrip(pOriginal, "<>WC"), tRepeated = $ZStrip(pRepeated, "<>WC")
	Quit:tRepeated="" 0
	Quit:tOriginal="" 0
	If $IsValidNum(tOriginal) {
		Quit:'$IsValidNum(tRepeated) 0
		Quit +tOriginal = +tRepeated
	}
	Quit $ZConvert(tOriginal, "U") = $ZConvert(tRepeated, "U")
}

/// The original value of the case behind a task: task, then decision trace, then the stored lab result.
ClassMethod OriginalValue(pTaskId As %String) As %String
{
	&sql(SELECT TOP 1 MessageControlId INTO :tControlId FROM Readback_Trace.Decision WHERE TaskId = :pTaskId ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	&sql(SELECT TOP 1 ValueText INTO :tValue FROM Readback_Msg.LabResult WHERE MessageControlId = :tControlId ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Quit tValue
}

ClassMethod Confirm(pTaskId As %String, pUser As %String)
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Trace.Decision WHERE TaskId = :pTaskId ORDER BY ID DESC)
	Quit:SQLCODE'=0
	Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tId)
	Set tTrace.ConfirmedBy = pUser, tTrace.ReadbackMatch = 1
	Set tTrace.ConfirmedAt = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Do tTrace.%Save()
}

}
