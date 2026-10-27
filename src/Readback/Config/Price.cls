/// Price of one model per million tokens, in USD. Empty prices mean the cost is unknown, never zero.
Class Readback.Config.Price Extends %Persistent
{

Property Model As %String(MAXLEN = 100) [ Required ];

Property InputPerMillion As %Numeric(SCALE = 6);

Property OutputPerMillion As %Numeric(SCALE = 6);

Property PriceDate As %Date [ Required ];

Index ModelIdx On Model [ Unique ];

Storage Default
{
<Data name="PriceDefaultData">
<Value name="1">
<Value>Model</Value>
</Value>
<Value name="2">
<Value>InputPerMillion</Value>
</Value>
<Value name="3">
<Value>OutputPerMillion</Value>
</Value>
<Value name="4">
<Value>PriceDate</Value>
</Value>
</Data>
<DataLocation>^Readback.Config.PriceD</DataLocation>
<DefaultData>PriceDefaultData</DefaultData>
<IdLocation>^Readback.Config.PriceD</IdLocation>
<IndexLocation>^Readback.Config.PriceI</IndexLocation>
<StreamLocation>^Readback.Config.PriceS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
