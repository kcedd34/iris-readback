/// Response class of the human review task. No read-back is needed; the reviewer records a note.
Class Readback.Workflow.ReviewTask Extends EnsLib.Workflow.TaskResponse
{

Method OnAction(pAction As %String) As %Status
{
	If pAction '= "Reviewed" {
		Quit $System.Status.Error(5001, "Only the action Reviewed completes a review task.")
	}
	Set tUser = $Select($IsObject(..%TaskStatus):..%TaskStatus.AssignedTo, 1:"")
	Set tSC = ##super(pAction)
	// Only a review that is allowed to complete feeds the memory of confirmed cases.
	If $System.Status.IsOK(tSC) { Do ..Record(..%Id(), tUser) }
	Quit tSC
}

/// Records who completed the review in the trace record of the task.
ClassMethod Record(pTaskId As %String, pUser As %String)
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Trace.Decision WHERE TaskId = :pTaskId ORDER BY ID DESC)
	Quit:SQLCODE'=0
	Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tId)
	Quit:'$IsObject(tTrace)
	Set tTrace.ReviewedBy = pUser, tTrace.ReviewedAt = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Do tTrace.%Save()
}

}
