/// Response class of the human review task. No read-back is needed; the reviewer records a note.
Class Readback.Workflow.ReviewTask Extends EnsLib.Workflow.TaskResponse
{

Method OnAction(pAction As %String) As %Status
{
	If pAction '= "Reviewed" {
		Quit $System.Status.Error(5001, "Only the action Reviewed completes a review task.")
	}
	Quit ##super(pAction)
}

}
