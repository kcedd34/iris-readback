/// Assigns a new task to a person of the role, in rotation, through the engine's own method
/// (EnsLib.Workflow.Engine.%TakeOwnershipForTask, docs/probes.md Probe 6).
Class Readback.Workflow.Assigner
{

/// Seconds to wait for the engine to create the worklist rows of a new task (they appeared within 150 ms).
Parameter WaitSeconds = 5;

/// Next person in rotation among pUsers (a $List), by name order. The counter is kept per role and wraps around.
ClassMethod PickUser(pRole As %String, pUsers As %List) As %String
{
	Quit:$ListLength(pUsers)=0 ""
	Set tSorted = ""
	Set tPtr = 0
	While $ListNext(pUsers, tPtr, tUser) { Set tSorted(tUser) = "" }
	Set tUser = "", tN = 0
	For { Set tUser = $Order(tSorted(tUser))  Quit:tUser=""
		Set tN = tN + 1, tNames(tN) = tUser
	}
	// $Increment is atomic: two processes assigning at the same time never take the same turn.
	Set tIndex = (($Increment(^Readback("rotation", pRole)) - 1) # tN) + 1
	Quit tNames(tIndex)
}

/// Finds the new unassigned task of a case (by the case id at the end of its subject), picks the next person of
/// the role and takes ownership for them. pUser is empty and the status still OK when no task appeared.
ClassMethod Assign(pRole As %String, pSubjectPrefix As %String, pControlId As %String, Output pTaskId As %String, Output pUser As %String) As %Status
{
	Set pTaskId = "", pUser = ""
	Set tSubject = pSubjectPrefix_pControlId
	Set tDeadline = $ZHorolog + ..#WaitSeconds
	Set tFound = 0
	For {
		Set tStmt = ##class(%SQL.Statement).%New()
		Set tSC = tStmt.%Prepare("SELECT ID, Task FROM EnsLib_Workflow.Worklist WHERE Task->%RoleName = ? AND Task->%Subject LIKE ? ORDER BY Task DESC")
		If $System.Status.IsError(tSC) { Quit }
		Set tRS = tStmt.%Execute(pRole, "%"_tSubject)
		If tRS.%SQLCODE < 0 { Set tSC = $System.Status.Error(5001, "worklist query failed: "_tRS.%Message)  Quit }
		Kill tUsers
		Set tTask = ""
		While tRS.%Next() {
			Set tId = tRS.%Get("Task")
			If tTask = "" {
				Set tTaskObj = ##class(EnsLib.Workflow.TaskResponse).%OpenId(tId)
				If $IsObject(tTaskObj) && $IsObject(tTaskObj.%TaskStatus) && (tTaskObj.%TaskStatus.AssignedTo = "") { Set tTask = tId }
			}
			If tId = tTask { Set tUsers($Piece(tRS.%Get("ID"), "||", 2)) = tRS.%Get("ID") }
		}
		If tTask '= "" { Set tFound = 1 }
		Quit:tFound
		Quit:($ZHorolog>tDeadline)
		Hang 0.1
	}
	If $System.Status.IsError($Get(tSC, 1)) Quit tSC
	If 'tFound Quit $$$OK
	Set tList = "", tName = ""
	For { Set tName = $Order(tUsers(tName))  Quit:tName=""  Set tList = tList_$ListBuild(tName) }
	Set pUser = ..PickUser(pRole, tList)
	Set pTaskId = tTask
	Set tSC = ##class(EnsLib.Workflow.Engine).%TakeOwnershipForTask(tUsers(pUser), pUser, .tMsg)
	If $System.Status.IsError(tSC) { Set pUser = "" }
	Quit tSC
}

}
