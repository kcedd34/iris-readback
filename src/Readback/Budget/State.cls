/// What the budget guard decided for one agent call. Not persisted: the trace record stores the fields.
Class Readback.Budget.State Extends %RegisteredObject
{

/// ok, result-ceiling or hourly-ceiling.
Property State As %String [ InitialExpression = "ok" ];

/// cost or tokens.
Property Basis As %String;

/// The amount used in the last 60 minutes, in the unit of the basis.
Property Used As %Numeric(SCALE = 6);

/// The ceiling in the unit of the basis.
Property Ceiling As %Numeric(SCALE = 6);

/// The estimate of this investigation in tokens, over the expected number of rounds.
Property EstimatedTokens As %Integer;

}
