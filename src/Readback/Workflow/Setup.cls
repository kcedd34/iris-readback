/// Creates the workflow roles, the workflow users and the matching security users. Idempotent.
/// The demo password comes from READBACK_DEMO_PASSWORD. When it is not set a random one is generated once,
/// kept for later runs and printed once in the container log. There is no default password.
Class Readback.Workflow.Setup
{

Parameter Communicators = "Readback.Communicators";

Parameter Reviewers = "Readback.Reviewers";

ClassMethod EnsureRoles() As %Status
{
	For tRole = ..#Communicators, ..#Reviewers {
		If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(tRole) { Set tSC = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(tRole)  Quit:$System.Status.IsError(tSC) }
	}
	Quit:$System.Status.IsError($Get(tSC, 1)) tSC
	Set tPassword = ..Password()
	Set tUsers = $ListBuild($ListBuild("communicator1", "Communicator One", ..#Communicators), $ListBuild("communicator2", "Communicator Two", ..#Communicators), $ListBuild("reviewer1", "Reviewer One", ..#Reviewers), $ListBuild("observer", "Observer without a role", ""))
	Set tPtr = 0
	While $ListNext(tUsers, tPtr, tU) {
		Set tName = $List(tU, 1), tFull = $List(tU, 2), tRole = $List(tU, 3)
		If '##class(EnsLib.Workflow.UserDefinition).%ExistsId(tName) { Set tSC = ##class(EnsLib.Workflow.UserDefinition).CreateUser(tName, tFull)  Quit:$System.Status.IsError(tSC) }
		If tRole '= "" {
			&sql(SELECT COUNT(*) INTO :tIn FROM EnsLib_Workflow.RoleMembership WHERE RoleName = :tRole AND UserName = :tName)
			If tIn = 0 { Set tSC = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(tRole, tName, 3, tFull)  Quit:$System.Status.IsError(tSC) }
		}
		Set tSC = ..EnsureSecurityUser(tName, tFull, tPassword)
		Quit:$System.Status.IsError(tSC)
	}
	Quit $Get(tSC, 1)
}

ClassMethod Password() As %String
{
	Set tPassword = $ZStrip($System.Util.GetEnviron("READBACK_DEMO_PASSWORD"), "<>WC")
	Quit:tPassword'="" tPassword
	If $Get(^Readback("demoPassword")) = "" {
		Set ^Readback("demoPassword") = $Translate($System.Encryption.Base64Encode($System.Encryption.GenCryptRand(12)), "+/=", "xyz")
		Write "Readback: no READBACK_DEMO_PASSWORD set; generated demo password (shown once): ", ^Readback("demoPassword"), !
	}
	Quit ^Readback("demoPassword")
}

ClassMethod EnsureSecurityUser(pName As %String, pFullName As %String, pPassword As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit:##class(Security.Users).Exists(pName) $$$OK
	Quit ##class(Security.Users).Create(pName, "%DB_USER,%EnsRole_WorkflowUser", pPassword, pFullName)
}

}
