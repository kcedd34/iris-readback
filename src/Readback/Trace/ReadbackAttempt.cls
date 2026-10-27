/// One read-back submission, matched or not. A communication counts only when Matched is true.
Class Readback.Trace.ReadbackAttempt Extends %Persistent
{

Property TaskId As %String(MAXLEN = 50) [ Required ];

Property AttemptNumber As %Integer;

Property UserName As %String(MAXLEN = 100);

Property ToldWho As %String(MAXLEN = 200);

/// The value as typed.
Property RepeatedValue As %String(MAXLEN = 200);

Property Matched As %Boolean;

Property AttemptedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

Index TaskIdx On TaskId;

Storage Default
{
<Data name="ReadbackAttemptDefaultData">
<Value name="1">
<Value>TaskId</Value>
</Value>
<Value name="2">
<Value>AttemptNumber</Value>
</Value>
<Value name="3">
<Value>UserName</Value>
</Value>
<Value name="4">
<Value>ToldWho</Value>
</Value>
<Value name="5">
<Value>RepeatedValue</Value>
</Value>
<Value name="6">
<Value>Matched</Value>
</Value>
<Value name="7">
<Value>AttemptedAt</Value>
</Value>
</Data>
<DataLocation>^Readback.Trace.ReadbackAttemptD</DataLocation>
<DefaultData>ReadbackAttemptDefaultData</DefaultData>
<IdLocation>^Readback.Trace.ReadbackAttemptD</IdLocation>
<IndexLocation>^Readback.Trace.ReadbackAttemptI</IndexLocation>
<StreamLocation>^Readback.Trace.ReadbackAttemptS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
