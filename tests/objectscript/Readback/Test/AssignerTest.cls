/// Rotation over the people of a role.
Class Readback.Test.AssignerTest Extends %UnitTest.TestCase
{

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^Readback("rotation", "TestRoleA"), ^Readback("rotation", "TestRoleB")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^Readback("rotation", "TestRoleA"), ^Readback("rotation", "TestRoleB")
	Quit $$$OK
}

Method TestThreeTasksTwoUsers()
{
	Set tUsers = $ListBuild("communicator2", "communicator1")
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleA", tUsers), "communicator1", "the first task goes to the first user by name")
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleA", tUsers), "communicator2", "the second to the second")
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleA", tUsers), "communicator1", "the third wraps to the first")
}

Method TestRotationIsPerRole()
{
	Do ##class(Readback.Workflow.Assigner).PickUser("TestRoleA", $ListBuild("a", "b"))
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleB", $ListBuild("x", "y")), "x", "another role starts from its own first user")
}

Method TestNoUsersGivesNobody()
{
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleA", ""), "", "an empty role gives nobody")
}

Method TestChangingMembershipDoesNotBreakRotation()
{
	Do ##class(Readback.Workflow.Assigner).PickUser("TestRoleB", $ListBuild("a", "b", "c"))
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleB", $ListBuild("a", "b")), "b", "the counter keeps going when a user leaves")
	Do $$$AssertEquals(##class(Readback.Workflow.Assigner).PickUser("TestRoleB", $ListBuild("a")), "a", "a single user always gets the task")
}

}
