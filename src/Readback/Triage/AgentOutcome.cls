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

/// live or replay.
Property Mode As %String;

Property Model As %String;

/// True when the call did not answer within the time limit.
Property TimedOut As %Boolean [ InitialExpression = 0 ];

Property TimeoutSeconds As %Integer [ InitialExpression = 30 ];

}
