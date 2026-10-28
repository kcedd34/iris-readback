/// Marks which confirmed cases are already in the case vector table.
Class Readback.Retrieval.IndexedCase Extends %Persistent
{

Property TraceId As %Integer [ Required ];

Property IndexedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

Index TraceIdx On TraceId [ Unique ];

Storage Default
{
<Data name="IndexedCaseDefaultData">
<Value name="1">
<Value>TraceId</Value>
</Value>
<Value name="2">
<Value>IndexedAt</Value>
</Value>
</Data>
<DataLocation>^Readback.Retrieval.IndexedCaseD</DataLocation>
<DefaultData>IndexedCaseDefaultData</DefaultData>
<IdLocation>^Readback.Retrieval.IndexedCaseD</IdLocation>
<IndexLocation>^Readback.Retrieval.IndexedCaseI</IndexLocation>
<StreamLocation>^Readback.Retrieval.IndexedCaseS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
