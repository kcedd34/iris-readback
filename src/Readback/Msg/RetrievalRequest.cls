/// Asks the retrieval operation for policy passages and similar confirmed cases.
Class Readback.Msg.RetrievalRequest Extends Ens.Request
{

/// The identifier-free description of the result (Readback.Retrieval.Describe).
Property Query As %String(MAXLEN = 2000) [ Required ];

Property MaxPassages As %Integer(MINVAL = 0) [ InitialExpression = 3 ];

Property MaxCases As %Integer(MINVAL = 0) [ InitialExpression = 3 ];

Storage Default
{
<Data name="RetrievalRequestDefaultData">
<Subscript>"RetrievalRequest"</Subscript>
<Value name="1">
<Value>Query</Value>
</Value>
<Value name="2">
<Value>MaxPassages</Value>
</Value>
<Value name="3">
<Value>MaxCases</Value>
</Value>
</Data>
<DefaultData>RetrievalRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
