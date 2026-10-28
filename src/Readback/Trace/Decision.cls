/// One record per triaged message: everything needed to rebuild the decision. Never holds a provider key.
Class Readback.Trace.Decision Extends %Persistent
{

Property MessageControlId As %String(MAXLEN = 50) [ Required ];

/// Joins to the message trace (Ens.MessageHeader and Ens_Util.Log).
Property SessionId As %Integer [ Required ];

/// live or replay.
Property Mode As %String(VALUELIST = ",live,replay");

/// The exact text sent to the agent.
Property InputText As %String(MAXLEN = "");

Property PromptVersion As %String(MAXLEN = 50);

Property Model As %String(MAXLEN = 100);

Property Provider As %String(MAXLEN = 50);

/// The answer text as received, kept even when invalid.
Property RawOutput As %String(MAXLEN = "");

Property SchemaValid As %Boolean;

Property FailureKind As %String(MAXLEN = 50);

Property FailureReason As %String(MAXLEN = 1000);

Property FloorSeverity As %Integer;

Property FloorRuleId As %String(MAXLEN = 100);

Property FloorNote As %String(MAXLEN = 300);

Property AgentDecision As %String(MAXLEN = 50);

Property AgentSeverity As %Integer;

Property AgentConfidence As %String(MAXLEN = 20);

Property Rationale As %String(MAXLEN = 1000);

/// JSON array text of the evidence identifiers.
Property Evidence As %String(MAXLEN = 1000);

Property FinalSeverity As %Integer;

Property Route As %String(MAXLEN = 20);

Property Divergence As %String(MAXLEN = 500);

Property InputTokens As %Integer;

Property OutputTokens As %Integer;

/// Empty when the price is unknown.
Property CostUsd As %Numeric(SCALE = 8);

Property CostKnown As %Boolean;

/// Wall clock around the agent call, retries included.
Property LatencyMs As %Integer;

/// In replay, the latency of the original call the recording was taken from; empty in live. LatencyMs keeps the
/// process's own measured time, because a replay is not a model call.
Property RecordedLatencyMs As %Integer;

Property TaskId As %String(MAXLEN = 50);

Property ConfirmedBy As %String(MAXLEN = 100);

Property ReadbackMatch As %Boolean;

Property ConfirmedAt As %TimeStamp;

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

Property OriginalValue As %String(MAXLEN = 100);

Property OriginalUnit As %String(MAXLEN = 50);

Property ConvertedValue As %String(MAXLEN = 100);

Property ConvertedUnit As %String(MAXLEN = 50);

/// converted, not-needed, not-convertible, unavailable or skipped.
Property ConversionOutcome As %String(MAXLEN = 30);

/// JSON array text of the policy passage identifiers given to the agent.
Property PassageIds As %String(MAXLEN = 1000);

/// JSON array text of the labels of the similar cases given to the agent.
Property CaseLabels As %String(MAXLEN = 1000);

/// JSON array text of the opaque trace ids behind those labels, for audit; never sent to the agent.
Property CaseTraceIds As %String(MAXLEN = 1000);

/// Hash of the policy file used; empty when retrieval was unavailable.
Property IndexVersion As %String(MAXLEN = 100);

Property RetrievalNote As %String(MAXLEN = 500);

/// ok, result-ceiling or hourly-ceiling.
Property BudgetState As %String(MAXLEN = 30);

/// cost or tokens.
Property BudgetBasis As %String(MAXLEN = 10);

Property BudgetUsed As %Numeric(SCALE = 6);

Property BudgetCeiling As %Numeric(SCALE = 6);

Property BudgetEstimate As %Integer;

Property ReviewedBy As %String(MAXLEN = 100);

Property ReviewedAt As %TimeStamp;

/// False when the budget stopped the agent call.
Property AgentCalled As %Boolean [ InitialExpression = 1 ];

Index CreatedIdx On CreatedAt;

Index ControlIdIdx On MessageControlId;

Index SessionIdx On SessionId;

Index TaskIdx On TaskId;

Storage Default
{
<Data name="DecisionDefaultData">
<Value name="1">
<Value>MessageControlId</Value>
</Value>
<Value name="2">
<Value>SessionId</Value>
</Value>
<Value name="3">
<Value>Mode</Value>
</Value>
<Value name="4">
<Value>InputText</Value>
</Value>
<Value name="5">
<Value>PromptVersion</Value>
</Value>
<Value name="6">
<Value>Model</Value>
</Value>
<Value name="7">
<Value>Provider</Value>
</Value>
<Value name="8">
<Value>RawOutput</Value>
</Value>
<Value name="9">
<Value>SchemaValid</Value>
</Value>
<Value name="10">
<Value>FailureKind</Value>
</Value>
<Value name="11">
<Value>FailureReason</Value>
</Value>
<Value name="12">
<Value>FloorSeverity</Value>
</Value>
<Value name="13">
<Value>FloorRuleId</Value>
</Value>
<Value name="14">
<Value>FloorNote</Value>
</Value>
<Value name="15">
<Value>AgentDecision</Value>
</Value>
<Value name="16">
<Value>AgentSeverity</Value>
</Value>
<Value name="17">
<Value>AgentConfidence</Value>
</Value>
<Value name="18">
<Value>Rationale</Value>
</Value>
<Value name="19">
<Value>Evidence</Value>
</Value>
<Value name="20">
<Value>FinalSeverity</Value>
</Value>
<Value name="21">
<Value>Route</Value>
</Value>
<Value name="22">
<Value>Divergence</Value>
</Value>
<Value name="23">
<Value>InputTokens</Value>
</Value>
<Value name="24">
<Value>OutputTokens</Value>
</Value>
<Value name="25">
<Value>CostUsd</Value>
</Value>
<Value name="26">
<Value>CostKnown</Value>
</Value>
<Value name="27">
<Value>LatencyMs</Value>
</Value>
<Value name="28">
<Value>TaskId</Value>
</Value>
<Value name="29">
<Value>ConfirmedBy</Value>
</Value>
<Value name="30">
<Value>ReadbackMatch</Value>
</Value>
<Value name="31">
<Value>ConfirmedAt</Value>
</Value>
<Value name="32">
<Value>CreatedAt</Value>
</Value>
<Value name="33">
<Value>OriginalValue</Value>
</Value>
<Value name="34">
<Value>OriginalUnit</Value>
</Value>
<Value name="35">
<Value>ConvertedValue</Value>
</Value>
<Value name="36">
<Value>ConvertedUnit</Value>
</Value>
<Value name="37">
<Value>ConversionOutcome</Value>
</Value>
<Value name="38">
<Value>PassageIds</Value>
</Value>
<Value name="39">
<Value>CaseLabels</Value>
</Value>
<Value name="40">
<Value>CaseTraceIds</Value>
</Value>
<Value name="41">
<Value>IndexVersion</Value>
</Value>
<Value name="42">
<Value>RetrievalNote</Value>
</Value>
<Value name="43">
<Value>BudgetState</Value>
</Value>
<Value name="44">
<Value>BudgetBasis</Value>
</Value>
<Value name="45">
<Value>BudgetUsed</Value>
</Value>
<Value name="46">
<Value>BudgetCeiling</Value>
</Value>
<Value name="47">
<Value>BudgetEstimate</Value>
</Value>
<Value name="48">
<Value>ReviewedBy</Value>
</Value>
<Value name="49">
<Value>ReviewedAt</Value>
</Value>
<Value name="50">
<Value>AgentCalled</Value>
</Value>
<Value name="51">
<Value>RecordedLatencyMs</Value>
</Value>
</Data>
<DataLocation>^Readback.Trace.DecisionD</DataLocation>
<DefaultData>DecisionDefaultData</DefaultData>
<IdLocation>^Readback.Trace.DecisionD</IdLocation>
<IndexLocation>^Readback.Trace.DecisionI</IndexLocation>
<StreamLocation>^Readback.Trace.DecisionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
