/// What retrieval found. Available false means retrieval itself failed: that is not the same as finding nothing.
Class Readback.Msg.RetrievalResponse Extends Ens.Response
{

Property Available As %Boolean [ InitialExpression = 0 ];

/// When not available: why, with any secret already redacted.
Property Reason As %String(MAXLEN = 500);

/// Hash of the policy file the passages come from.
Property IndexVersion As %String(MAXLEN = 100);

Property Passages As list Of Readback.Msg.RetrievalItem;

Property Cases As list Of Readback.Msg.RetrievalItem;

Storage Default
{
<Data name="RetrievalResponseDefaultData">
<Subscript>"RetrievalResponse"</Subscript>
<Value name="1">
<Value>Available</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
<Value name="3">
<Value>IndexVersion</Value>
</Value>
<Value name="4">
<Value>Passages</Value>
</Value>
<Value name="5">
<Value>Cases</Value>
</Value>
</Data>
<DefaultData>RetrievalResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
