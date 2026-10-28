/// What came back from the agent step, before any validation. Built by the process and by tests.
Class Readback.Triage.AgentOutcome Extends %RegisteredObject
{

/// Status of the call. An error status carries the platform's error text.
Property Status As %Status [ InitialExpression = 1 ];

/// The answer text (empty on error).
Property Content As %String(MAXLEN = "");

Property InputTokens As %Integer [ InitialExpression = 0 ];

Property OutputTokens As %Integer [ InitialExpression = 0 ];

/// Wall clock around the call, retries included.
Property LatencyMs As %Integer;

/// In replay, the latency of the original call, taken from the recording; empty otherwise.
Property RecordedLatencyMs As %Integer;

/// live or replay.
Property Mode As %String;

Property Model As %String;

/// True when the call did not answer within the time limit.
Property TimedOut As %Boolean [ InitialExpression = 0 ];

Property TimeoutSeconds As %Integer [ InitialExpression = 30 ];

/// False when the budget stopped the call: no request was made.
Property AgentCalled As %Boolean [ InitialExpression = 1 ];

/// ok, result-ceiling or hourly-ceiling.
Property BudgetState As %String [ InitialExpression = "ok" ];

/// cost or tokens.
Property BudgetBasis As %String;

Property BudgetUsed As %Numeric(SCALE = 6);

Property BudgetCeiling As %Numeric(SCALE = 6);

Property BudgetEstimate As %Integer;

/// converted, not-needed, not-convertible, unavailable or skipped.
Property ConversionOutcome As %String;

/// True when retrieval itself failed (as opposed to finding nothing): the agent is not called.
Property RetrievalFailed As %Boolean [ InitialExpression = 0 ];

/// Why retrieval failed, empty when it did not.
Property RetrievalNote As %String(MAXLEN = 500);

}
