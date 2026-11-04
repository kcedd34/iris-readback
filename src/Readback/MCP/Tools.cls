/// The tool set of the read-only MCP server: four tools, all read-only. There is no tool that confirms a read-back, closes an alert, completes
/// a task or sends anything, and that is a decision, not a gap: a person must repeat the value (P-4), so an AI assistant never closes a critical.
Class Readback.MCP.Tools Extends %AI.ToolSet [ DependsOn = Readback.MCP.Impl ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="ReadbackMcpTools">
  <Description>Read-only tools over the Readback decisions and the measured evaluation. None of them confirms a read-back.</Description>
  <Tool Name="list_pending_criticals" Class="Readback.MCP.Impl" Method="ListPendingCriticals">
    <Description>The critical results that are waiting for a person to repeat the value (the read-back), with the case id, the analyte, since when, who they are assigned to and the state of their alert. Takes no argument. It cannot confirm anything.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="explain_decision" Class="Readback.MCP.Impl" Method="ExplainDecision">
    <Description>Explains one decision from its trace record: the rule that set the floor, the agent's answer and rationale, the composition, the tool calls in order and what a person did. Pass the case id, for example RB2026-00001-S1. Never a patient identifier.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="read_evaluation" Class="Readback.MCP.Impl" Method="ReadEvaluation">
    <Description>The measured evaluation over 240 synthetic cases for two models: confusion matrices, silenced and missed criticals, cost and latency. Takes no argument.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="read_ablation" Class="Readback.MCP.Impl" Method="ReadAblation">
    <Description>The ablation: which layer keeps a critical result from being released (range rule, change rule, release guard, agent), with and without the change rule's verdict. Takes no argument.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
