/// The security of the MCP server: a resource, a role that holds it, and the web application. Idempotent. The role is given to the
/// read-only demonstration account and to nobody else.
Class Readback.MCP.Setup
{

Parameter Resource = "Readback_MCP";

Parameter Role = "ReadbackMcp";

Parameter Path = "/readback/mcp";

/// The resource and the role, so that an account can be given the role.
ClassMethod EnsureSecurity() As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Resources).Exists(..#Resource) {
		Set tSC = ##class(Security.Resources).Create(..#Resource, "Use of the Readback read-only MCP server", "")
		Quit:$System.Status.IsError(tSC) tSC
	}
	If '##class(Security.Roles).Exists(..#Role) {
		Set tSC = ##class(Security.Roles).Create(..#Role, "Use of the Readback read-only MCP server", ..#Resource_":U")
		Quit:$System.Status.IsError(tSC) tSC
	}
	Quit $$$OK
}

/// The web application of the service. Its type must carry the MCP Server bit (16) next to the REST one (2): an application of type 2
/// only is answered with a 404 by the platform's MCP gateway (iris-mcp-server) for every request that carries credentials, and the
/// gateway then reports that the endpoint did not identify itself (docs/probes.md, Probe 16).
ClassMethod EnsureWebApp() As %Status
{
	Set tSC = ..EnsureSecurity()
	Quit:$System.Status.IsError(tSC) tSC
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Applications).Exists(..#Path) {
		Set tSC = ##class(Security.Applications).Get(..#Path, .tProps)
		Quit:$System.Status.IsError(tSC) tSC
		If (+$Get(tProps("Type")) \ 16) # 2 { Quit $$$OK }
		Set tProps("Type") = +$Get(tProps("Type")) + 16
		Quit ##class(Security.Applications).Modify(..#Path, .tProps)
	}
	Set tProps("DispatchClass") = "Readback.MCP.Service"
	Set tProps("NameSpace") = "USER"
	Set tProps("Enabled") = 1
	Set tProps("AutheEnabled") = 32
	Set tProps("Type") = 18
	Set tProps("Description") = "Readback read-only MCP server"
	Quit ##class(Security.Applications).Create(..#Path, .tProps)
}

}
