/// The routed outcome of a triage, sent to the outcome operation for logging.
Class Readback.Msg.Outcome Extends Ens.Request
{

Property MessageControlId As %String(MAXLEN = 50);

Property Route As %String(MAXLEN = 20);

Property FinalSeverity As %Integer;

Property Reason As %String(MAXLEN = 500);

Property Mode As %String(MAXLEN = 10);

Storage Default
{
<Data name="OutcomeDefaultData">
<Subscript>"Outcome"</Subscript>
<Value name="1">
<Value>MessageControlId</Value>
</Value>
<Value name="2">
<Value>Route</Value>
</Value>
<Value name="3">
<Value>FinalSeverity</Value>
</Value>
<Value name="4">
<Value>Reason</Value>
</Value>
<Value name="5">
<Value>Mode</Value>
</Value>
</Data>
<DefaultData>OutcomeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
