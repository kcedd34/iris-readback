/// P-7: the decision taken before every agent call. A ceiling that is reached means no call; the case then
/// follows the floor alone (Readback.Triage.Composer applies the usual rule to the budget-reached failure).
Class Readback.Budget.Guard
{

/// Tokens of a request: characters divided by 4 rounded up. A deliberate over-estimate; the real count is
/// stored with the trace after the call.
ClassMethod EstimateTokens(pChars As %Integer) As %Integer
{
	Quit $Select(pChars#4=0:pChars\4, 1:pChars\4+1)
}

/// Tokens the tool definitions add to every round of the request: a deliberate over-estimate, since the definitions are
/// sent again on each round.
Parameter ToolDefinitionTokens = 450;

/// The decision for one investigation. pText is the user text of the case. The estimate counts every round the agent is
/// expected to use (the configuration says how many), because each round sends the whole conversation again plus the
/// tool definitions, and each tool round adds a result. A ceiling that is reached means no call. The iteration limit set
/// on the session is the hard stop; the real tokens of the whole investigation come from the session statistics.
ClassMethod Check(pText As %String, pModel As %String = "") As Readback.Budget.State
{
	Set tState = ##class(Readback.Budget.State).%New()
	Set tBudget = ##class(Readback.Config.Budget).Current()
	Set tBounds = ##class(Readback.Config.AgentTools).Current()
	If '$IsObject(tBudget) || '$IsObject(tBounds) {
		// No ceilings or no bounds loaded: refuse the call rather than run without a budget.
		Set tState.State = "result-ceiling", tState.Basis = "tokens"
		Quit tState
	}
	Set tState.EstimatedTokens = ..EstimateInvestigation(pText, tBounds)
	Do ..Window(pModel, tBudget, tState)
	If tState.EstimatedTokens > tBudget.PerResultTokens {
		Set tState.State = "result-ceiling"
	} ElseIf tState.Used >= tState.Ceiling {
		Set tState.State = "hourly-ceiling"
	}
	Quit tState
}

/// The tokens an investigation of the expected number of rounds may use: the request of each round (system prompt, case
/// text, tool definitions and the results gathered so far) and the answers (short for a tool round, up to the cap for the
/// last one).
ClassMethod EstimateInvestigation(pText As %String, pBounds As Readback.Config.AgentTools) As %Integer
{
	Set tRounds = pBounds.ExpectedRounds
	Set tBase = ..EstimateTokens($Length(##class(Readback.Triage.Prompt).Text()) + $Length(pText)) + ..#ToolDefinitionTokens
	Set tResultTokens = ..EstimateTokens(pBounds.ToolResultMaxChars)
	Set tOutput = (tRounds - 1) * 80 + ##class(Readback.Triage.Schema).#MaxTokens
	// ObjectScript evaluates left to right, so every product is parenthesized before it is added.
	Quit (tRounds * tBase) + (((tRounds - 1) * tRounds / 2) * tResultTokens) + tOutput
}

/// Fills Basis, Used and Ceiling of pState from the agent calls of the last 60 minutes in the trace.
ClassMethod Window(pModel As %String, pBudget As Readback.Config.Budget, pState As Readback.Budget.State)
{
	Set tCut = ..WindowStart()
	Set tCost = 0, tTokens = 0
	&sql(SELECT COALESCE(SUM(CASE WHEN CostKnown = 1 THEN CostUsd ELSE 0 END), 0), COALESCE(SUM(COALESCE(InputTokens,0) + COALESCE(OutputTokens,0)), 0)
	     INTO :tCost, :tTokens
	     FROM Readback_Trace.Decision WHERE AgentCalled = 1 AND CreatedAt >= :tCut)
	If SQLCODE < 0 {
		// A window that cannot be read counts as full: the safe side of a budget.
		Set pState.Basis = "tokens", pState.Used = pBudget.HourlyTokens, pState.Ceiling = pBudget.HourlyTokens
		Quit
	}
	Do ##class(Readback.Config.Cost).Compute(pModel, 1, 1, .tKnown)
	If tKnown {
		Set pState.Basis = "cost", pState.Used = tCost, pState.Ceiling = pBudget.HourlyCostUsd
	} Else {
		Set pState.Basis = "tokens", pState.Used = tTokens, pState.Ceiling = pBudget.HourlyTokens
	}
}

/// The state of the window as it stands now, for the status endpoint: reached or ok.
ClassMethod Now(pModel As %String = "") As %DynamicObject
{
	Set tBudget = ##class(Readback.Config.Budget).Current()
	If '$IsObject(tBudget) { Quit {"state":"reached","basis":"tokens","used":0,"ceiling":0,"perResultTokens":0,"hourlyCostUsd":0,"hourlyTokens":0} }
	Set tState = ##class(Readback.Budget.State).%New()
	Do ..Window(pModel, tBudget, tState)
	Quit {"state":($Select(tState.Used>=tState.Ceiling:"reached", 1:"ok")),"basis":(tState.Basis),"used":(+tState.Used),"ceiling":(+tState.Ceiling),"perResultTokens":(tBudget.PerResultTokens),"hourlyCostUsd":(+tBudget.HourlyCostUsd),"hourlyTokens":(tBudget.HourlyTokens)}
}

/// The timestamp 60 minutes ago in the format of CreatedAt (UTC).
ClassMethod WindowStart() As %String
{
	Set tNow = $ZTimeStamp, tDay = $Piece(tNow, ",", 1), tSec = $Piece(tNow, ",", 2) - 3600
	If tSec < 0 { Set tSec = tSec + 86400, tDay = tDay - 1 }
	Quit $ZDateTime(tDay_","_tSec, 3, 1, 3)
}

}
