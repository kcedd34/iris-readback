/// The read-only MCP server of the product: the platform's own MCP service over the tools of Readback.MCP.Tools. Reached through the
/// management web port (not through the public proxy), by an account that holds the Readback_MCP resource. It lists the pending criticals,
/// explains a decision from its trace and reads the evaluation and the ablation. It never confirms a read-back (P-4).
Class Readback.MCP.Service Extends %AI.MCP.Service [ DependsOn = Readback.MCP.Tools ]
{

Parameter SPECIFICATION = "Readback.MCP.Tools";

/// Only an account that holds this resource may use the service; the web application adds no other way in.
Parameter RESOURCE = "Readback_MCP";

/// The same resource under the name build 109 reads: from that build the platform's service does no authorization unless this parameter (or
/// OnAuthenticate) says so, and it ignores RESOURCE. Both are set so that either build enforces the resource; each tool also checks it itself
/// (Readback.MCP.Impl), so a later change of the platform's mechanism cannot open the service.
Parameter SECURITYRESOURCE = "Readback_MCP";

Parameter VERSION = "Readback read-only MCP service";

}
