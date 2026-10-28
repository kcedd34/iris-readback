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

/// The estimate of this call in tokens, after any items were dropped.
Property EstimatedTokens As %Integer;

/// How many retrieved items were dropped to fit the per-result ceiling.
Property Reduced As %Integer [ InitialExpression = 0 ];

/// How many policy passages and similar cases remain after the drops.
Property PassagesKept As %Integer;

Property CasesKept As %Integer;

}
