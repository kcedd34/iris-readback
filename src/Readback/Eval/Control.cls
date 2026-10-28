/// What an evaluation run needs to control in the running product: a clean state, the model, the output cap, the
/// replay set and the budget ceilings. Every call is meant to be made from a terminal script, one block per line.
Class Readback.Eval.Control
{

/// How long the agent item's jobs need to be back after a setting change (Probe 13).
Parameter JOBWAIT = 25;

/// True when no decision has been traced and no confirmed case is in the retrieval pool: runs of different models then
/// see the same retrieval state and the pool cannot grow during a run. pWhy says what is not clean.
ClassMethod IsClean(Output pWhy As %String) As %Boolean
{
	Set pWhy = ""
	&sql(SELECT COUNT(*) INTO :tRows FROM Readback_Trace.Decision)
	If SQLCODE < 0 { Set pWhy = "the trace could not be read (SQLCODE "_SQLCODE_")" }
	ElseIf tRows > 0 { Set pWhy = tRows_" trace rows exist" }
	Quit:pWhy'="" 0
	Set tCases = ##class(Readback.Retrieval.Engine).Snapshot().confirmedCases
	If tCases > 0 { Set pWhy = tCases_" confirmed cases are in the retrieval pool" }
	Quit:pWhy'="" 0
	Quit 1
}

/// Sets the model of the live agent item and waits for its jobs. The update re-saves the item as the class defines it
/// (disabled), so the item is enabled again afterwards.
ClassMethod UseModel(pModel As %String, pWait As %Integer = {..#JOBWAIT}) As %Status
{
	Quit:pModel="" $System.Status.Error(5001, "a model name is required")
	Set tSC = ##class(Ens.Director).SetAdapterSettingValue("Readback.Agent", "Model", pModel)
	Quit:$System.Status.IsError(tSC) tSC
	Quit ..Restart(pWait)
}

/// Sets the output cap sent to the provider (max_completion_tokens in the extra parameters of the session configuration).
ClassMethod UseOutputCap(pTokens As %Integer, pWait As %Integer = {..#JOBWAIT}) As %Status
{
	Quit:(pTokens '= (+pTokens \ 1))!(pTokens < 1) $System.Status.Error(5001, "the output cap must be a positive integer")
	Set tCurrent = "{""max_completion_tokens"":"_##class(Readback.Triage.Schema).#MaxTokens_"}"
	Set tText = $Replace(##class(Readback.Triage.Schema).SessionConfigJSON(), tCurrent, "{""max_completion_tokens"":"_pTokens_"}")
	Set tSC = ##class(Ens.Director).SetAdapterSettingValue("Readback.Agent", "SessionConfigString", tText)
	Quit:$System.Status.IsError(tSC) tSC
	Quit ..Restart(pWait)
}

/// Applies the settings changed so far and makes sure the agent item is enabled and its jobs are back.
ClassMethod Restart(pWait As %Integer = {..#JOBWAIT}) As %Status
{
	Set tSC = ##class(Ens.Director).UpdateProduction(30, 1)
	Quit:$System.Status.IsError(tSC) tSC
	If '##class(Ens.Director).IsItemEnabled("Readback.Agent") { Set tSC = ##class(Ens.Director).EnableConfigItem("Readback.Agent", 1) }
	Quit:$System.Status.IsError(tSC) tSC
	Hang pWait
	Quit $$$OK
}

/// Selects the replay set the replay item reads; it takes effect for the next case.
ClassMethod UseReplaySet(pSet As %String) As %Status
{
	Quit:pSet="" $System.Status.Error(5001, "a replay set name is required")
	Quit ##class(Readback.Replay.Recording).Activate(pSet)
}

/// Writes the three ceilings and returns the previous values in pPrevious, to restore afterwards.
ClassMethod UseCeilings(pPerResultTokens As %Integer, pHourlyCostUsd As %Numeric, pHourlyTokens As %Integer, Output pPrevious As %DynamicObject) As %Status
{
	Set tBudget = ##class(Readback.Config.Budget).Current()
	Quit:'$IsObject(tBudget) $System.Status.Error(5001, "no budget ceilings are loaded")
	Set pPrevious = {"perResultTokens":(+tBudget.PerResultTokens), "hourlyCostUsd":(+tBudget.HourlyCostUsd), "hourlyTokens":(+tBudget.HourlyTokens)}
	Set tBudget.PerResultTokens = pPerResultTokens, tBudget.HourlyCostUsd = pHourlyCostUsd, tBudget.HourlyTokens = pHourlyTokens
	Quit tBudget.%Save()
}

/// Puts back the ceilings returned by UseCeilings.
ClassMethod RestoreCeilings(pPrevious As %DynamicObject) As %Status
{
	Quit:'$IsObject(pPrevious) $System.Status.Error(5001, "no previous ceilings to restore")
	Quit ..UseCeilings(pPrevious.perResultTokens, pPrevious.hourlyCostUsd, pPrevious.hourlyTokens, .tIgnored)
}

/// The current ceilings as a JSON object, to restore them in a later session.
ClassMethod CeilingsJson() As %String
{
	Set tBudget = ##class(Readback.Config.Budget).Current()
	Quit:'$IsObject(tBudget) "{}"
	Quit {"perResultTokens":(+tBudget.PerResultTokens), "hourlyCostUsd":(+tBudget.HourlyCostUsd), "hourlyTokens":(+tBudget.HourlyTokens)}.%ToJSON()
}

/// The current ceilings as text for the report header.
ClassMethod CeilingsText() As %String
{
	Set tBudget = ##class(Readback.Config.Budget).Current()
	Quit:'$IsObject(tBudget) "none loaded"
	Quit "per result "_tBudget.PerResultTokens_" tokens; per hour "_(+tBudget.HourlyCostUsd)_" USD or "_tBudget.HourlyTokens_" tokens"
}

}
