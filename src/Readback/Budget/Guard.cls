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

/// The decision for one call. pText is the full request text; pPassageChars and pCaseChars are $Lists with
/// the number of characters each retrieved item adds to the text (empty when nothing was retrieved). Items are
/// dropped from the end, similar cases first, until the estimate fits the per-result ceiling.
ClassMethod Check(pText As %String, pPassageChars As %List = "", pCaseChars As %List = "", pModel As %String = "") As Readback.Budget.State
{
	Set tState = ##class(Readback.Budget.State).%New()
	Set tBudget = ##class(Readback.Config.Budget).Current()
	If '$IsObject(tBudget) {
		// No ceilings loaded: refuse the call rather than run without a budget.
		Set tState.State = "result-ceiling", tState.Basis = "tokens"
		Quit tState
	}
	Set tPassages = $ListLength(pPassageChars), tCases = $ListLength(pCaseChars)
	Set tChars = $Length(pText)
	Set tMax = ##class(Readback.Triage.Schema).#MaxTokens
	Set tEstimate = ..EstimateTokens(tChars) + tMax
	While (tEstimate > tBudget.PerResultTokens) && ((tCases > 0) || (tPassages > 0)) {
		If tCases > 0 {
			Set tChars = tChars - $ListGet(pCaseChars, tCases), tCases = tCases - 1
		} Else {
			Set tChars = tChars - $ListGet(pPassageChars, tPassages), tPassages = tPassages - 1
		}
		Set tState.Reduced = tState.Reduced + 1
		Set tEstimate = ..EstimateTokens(tChars) + tMax
	}
	Set tState.EstimatedTokens = tEstimate, tState.PassagesKept = tPassages, tState.CasesKept = tCases
	Do ..Window(pModel, tBudget, tState)
	If tEstimate > tBudget.PerResultTokens {
		Set tState.State = "result-ceiling"
	} ElseIf tState.Used >= tState.Ceiling {
		Set tState.State = "hourly-ceiling"
	}
	Quit tState
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
