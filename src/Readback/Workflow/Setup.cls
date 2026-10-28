/// Creates the workflow roles, the workflow users and the matching security users. Idempotent.
/// The demo password comes from READBACK_DEMO_PASSWORD. When it is not set a random one is generated once,
/// kept for later runs and printed once in the container log. There is no default password.
Class Readback.Workflow.Setup
{

Parameter Communicators = "Readback.Communicators";

Parameter Reviewers = "Readback.Reviewers";

Parameter Capacity = 10000;

ClassMethod EnsureRoles() As %Status
{
	For tRole = ..#Communicators, ..#Reviewers {
		If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(tRole) { Set tSC = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(tRole)  Quit:$System.Status.IsError(tSC) }
		// The engine stops giving tasks to a person who already holds this many (default 100). A critical
		// result must never wait for a free slot, so the limit is raised well above any realistic backlog.
		Set tRoleObj = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(tRole)
		If tRoleObj.Capacity < ..#Capacity {
			Set tRoleObj.Capacity = ..#Capacity
			Set tSC = tRoleObj.%Save()
			Quit:$System.Status.IsError(tSC)
		}
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
	Set tSC = ..EnsureApiRole()
	Quit:$System.Status.IsError(tSC) tSC
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(pName) {
		Quit ##class(Security.Users).Create(pName, "%DB_USER,%EnsRole_WorkflowUser,ReadbackApi", pPassword, pFullName)
	}
	// Existing user from an earlier run: make sure it has the API role.
	Set tSC = ##class(Security.Users).Get(pName, .tProps)
	Quit:$System.Status.IsError(tSC) tSC
	If (","_tProps("Roles")_",") [ ",ReadbackApi," { Quit $$$OK }
	Set tProps("Roles") = tProps("Roles")_$Select(tProps("Roles")="":"", 1:",")_"ReadbackApi"
	Quit ##class(Security.Users).Modify(pName, .tProps)
}

/// The role that lets the demo users read the status tables through /readback/api: SELECT only, on the
/// tables the endpoint reads. Nothing broader is granted.
ClassMethod EnsureApiRole() As %Status
{
	New $Namespace
	Set tNs = $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Roles).Exists("ReadbackApi") {
		Set tSC = ##class(Security.Roles).Create("ReadbackApi", "Read access to the Readback status tables")
		Quit:$System.Status.IsError(tSC) tSC
	}
	Set $Namespace = tNs
	For tTable = "Readback_Config.Range", "Readback_Config.Price", "Readback_Replay.Recording", "Readback_Trace.Decision", "Readback_Config.Budget" {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "GRANT SELECT ON "_tTable_" TO ReadbackApi")
		If tRS.%SQLCODE < 0 { Quit }
	}
	Quit:tRS.%SQLCODE<0 $System.Status.Error(5001, "grant failed: "_tRS.%Message)
	Quit $$$OK
}

}
