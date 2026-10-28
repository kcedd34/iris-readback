/// One retrieved item: a policy passage or a similar confirmed case.
Class Readback.Msg.RetrievalItem Extends (%SerialObject, %XML.Adaptor)
{

/// Passage id, or the label of a case (similar-case-1, ...).
Property Id As %String(MAXLEN = 100);

Property Source As %String(MAXLEN = 100);

Property Title As %String(MAXLEN = 200);

/// The passage text, or the identifier-free description of a case.
Property Text As %String(MAXLEN = 2000);

/// Cases only.
Property Decision As %String(MAXLEN = 100);

Property Route As %String(MAXLEN = 30);

/// Opaque trace record id of a case, for audit. Never sent to the agent.
Property TraceId As %String(MAXLEN = 50);

Property Score As %Numeric(SCALE = 6);

Storage Default
{
<Data name="RetrievalItemState">
<Value name="1">
<Value>Id</Value>
</Value>
<Value name="2">
<Value>Source</Value>
</Value>
<Value name="3">
<Value>Title</Value>
</Value>
<Value name="4">
<Value>Text</Value>
</Value>
<Value name="5">
<Value>Decision</Value>
</Value>
<Value name="6">
<Value>Route</Value>
</Value>
<Value name="7">
<Value>TraceId</Value>
</Value>
<Value name="8">
<Value>Score</Value>
</Value>
</Data>
<State>RetrievalItemState</State>
<StreamLocation>^Readback.Msg.RetrievalItemS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
