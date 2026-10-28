/// The ceilings of the agent budget. One row, loaded from data/config/budget.json.
Class Readback.Config.Budget Extends %Persistent
{

/// Integer greater than 0: the most tokens one agent call (request plus longest answer) may use.
Property PerResultTokens As %Integer(MINVAL = 1) [ Required ];

/// Number greater than 0: the most the agent calls of the last 60 minutes may cost, in USD.
Property HourlyCostUsd As %Numeric(MINVAL = 0.000001, SCALE = 6) [ Required ];

/// Integer greater than 0: the most tokens the agent calls of the last 60 minutes may use.
Property HourlyTokens As %Integer(MINVAL = 1) [ Required ];

/// The current ceilings, or "" when none are loaded.
ClassMethod Current() As Readback.Config.Budget
{
	&sql(SELECT TOP 1 ID INTO :tId FROM Readback_Config.Budget ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Quit ..%OpenId(tId)
}

Storage Default
{
<Data name="BudgetDefaultData">
<Value name="1">
<Value>PerResultTokens</Value>
</Value>
<Value name="2">
<Value>HourlyCostUsd</Value>
</Value>
<Value name="3">
<Value>HourlyTokens</Value>
</Value>
</Data>
<DataLocation>^Readback.Config.BudgetD</DataLocation>
<DefaultData>BudgetDefaultData</DefaultData>
<IdLocation>^Readback.Config.BudgetD</IdLocation>
<IndexLocation>^Readback.Config.BudgetI</IndexLocation>
<StreamLocation>^Readback.Config.BudgetS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
