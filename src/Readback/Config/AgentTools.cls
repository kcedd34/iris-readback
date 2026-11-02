/// The bounds of the agent investigation. One row, loaded from data/config/agent-tools.json.
Class Readback.Config.AgentTools Extends %Persistent
{

/// Integer greater than 0: the most model rounds one case may use. Set on every agent session.
Property MaxIterations As %Integer(MINVAL = 1) [ Required ];

/// Integer greater than 0: the most tool calls one case may make.
Property MaxToolCalls As %Integer(MINVAL = 1) [ Required ];

/// Integer greater than 0: the most characters a tool result may hold.
Property ToolResultMaxChars As %Integer(MINVAL = 1) [ Required ];

/// Integer greater than 0: the rounds the budget estimate assumes for one case.
Property ExpectedRounds As %Integer(MINVAL = 1) [ Required ];

/// The current bounds, or "" when none are loaded. A caller that gets "" must not call the agent.
ClassMethod Current() As Readback.Config.AgentTools
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Config.AgentTools ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Quit ..%OpenId(tId)
}

}
