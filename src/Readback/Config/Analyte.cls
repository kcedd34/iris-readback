/// The reference unit of an analyte, and its molar mass when a mass concentration has to be converted to an
/// amount concentration. Loaded from data/config/analytes.json.
Class Readback.Config.Analyte Extends %Persistent
{

Property AnalyteCode As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

Property Name As %String(MAXLEN = 100) [ Required ];

/// A UCUM unit. Every Readback.Config.Range row of the analyte uses exactly this unit (checked at load).
Property ReferenceUnit As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

/// Optional, g/mol, greater than 0.
Property MolarMass As %Numeric(MINVAL = 0.000001, SCALE = 6);

Index CodeIdx On AnalyteCode [ Unique ];

Storage Default
{
<Data name="AnalyteDefaultData">
<Value name="1">
<Value>AnalyteCode</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>ReferenceUnit</Value>
</Value>
<Value name="4">
<Value>MolarMass</Value>
</Value>
</Data>
<DataLocation>^Readback.Config.AnalyteD</DataLocation>
<DefaultData>AnalyteDefaultData</DefaultData>
<IdLocation>^Readback.Config.AnalyteD</IdLocation>
<IndexLocation>^Readback.Config.AnalyteI</IndexLocation>
<StreamLocation>^Readback.Config.AnalyteS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
