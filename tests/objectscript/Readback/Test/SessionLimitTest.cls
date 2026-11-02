/// No agent session is created without its iteration limit: the platform's loop has no bound of its own and keeps
/// calling the model after the caller has given up. Only Readback.Agent.Operation creates a session, and it sets the
/// limit from the configuration before it does.
Class Readback.Test.SessionLimitTest Extends %UnitTest.TestCase
{

Method TestOnlyTheOperationCreatesASession()
{
	Set tOffenders = "", tScanned = 0
	Set tStmt = ##class(%SQL.Statement).%New()
	Do tStmt.%Prepare("SELECT parent, Name FROM %Dictionary.CompiledMethod WHERE parent LIKE 'Readback.%' AND parent NOT LIKE 'Readback.Test.%' AND parent <> 'Readback.Agent.Operation'")
	Set tRS = tStmt.%Execute()
	While tRS.%Next() {
		Set tMethod = ##class(%Dictionary.CompiledMethod).%OpenId(tRS.%Get("parent")_"||"_tRS.%Get("Name"))
		Continue:'$IsObject(tMethod)
		Set tScanned = tScanned + 1
		Set tCode = tMethod.Implementation.Read(1000000)
		If (tCode [ "CreateSession(") || (tCode [ "%AI.Agent.Session).Create") || (tCode [ "OpenSession(") || (tCode [ "ResumeSession(") {
			Set tOffenders = tOffenders_" "_tRS.%Get("parent")_"::"_tRS.%Get("Name")
		}
	}
	Do $$$AssertTrue(tScanned > 10, "methods were scanned ("_tScanned_")")
	Do $$$AssertEquals(tOffenders, "", "no class other than the agent operation creates or resumes a session:"_tOffenders)
}

Method TestTheOperationSetsTheLimitBeforeItCreatesTheSession()
{
	Set tMethod = ##class(%Dictionary.CompiledMethod).%OpenId("Readback.Agent.Operation||handleText")
	Do $$$AssertTrue($IsObject(tMethod), "the operation's text handler exists")
	Set tCode = tMethod.Implementation.Read(1000000)
	Set tLimit = $Find(tCode, "max_iterations")
	Set tCreate = $Find(tCode, "CreateSession(")
	Do $$$AssertTrue(tLimit > 0, "the handler sets max_iterations")
	Do $$$AssertTrue(tCreate > 0, "the handler creates the session")
	Do $$$AssertTrue(tLimit < tCreate, "and sets the limit before it creates the session")
	Do $$$AssertTrue(tCode [ "MaxIterations", "from the configuration, not a constant")
	Do $$$AssertTrue(tCode [ "no agent call is made", "and refuses to call the agent when the bounds are not loaded")
}

Method TestNoAgentSessionIsCreatedWithoutTheBounds()
{
	Set tRow = ##class(Readback.Config.AgentTools).Current()
	Do $$$AssertTrue($IsObject(tRow), "the shipped bounds are loaded")
	Do ##class(Readback.Config.AgentTools).%KillExtent()
	Set tGuard = ##class(Readback.Budget.Guard).Check("short")
	Do $$$AssertEquals(tGuard.State, "result-ceiling", "without the bounds the budget guard refuses the call")
	Do ##class(Readback.Config.Loader).LoadAll()
	Do $$$AssertTrue($IsObject(##class(Readback.Config.AgentTools).Current()), "and the bounds are loaded again")
}

}
