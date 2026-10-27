/// One critical range row: the severity floor for an analyte, unit and age group.
/// The table is loaded from data/config/critical-ranges.json. Demonstration values only.
Class Readback.Config.Range Extends %Persistent
{

/// Analyte code as received in OBX-3.1.
Property AnalyteCode As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

/// Unit exactly as received in OBX-6, case-sensitive.
Property Unit As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

Property AgeGroup As %String(VALUELIST = ",neonate,child,adult") [ Required ];

/// A value at or below this limit is critical.
Property CriticalLow As %Numeric(SCALE = 4);

/// A value at or above this limit is critical.
Property CriticalHigh As %Numeric(SCALE = 4);

/// Severity assigned by the rule, 0 to 3.
Property FloorSeverity As %Integer(MAXVAL = 3, MINVAL = 0) [ Required ];

/// Where the range comes from, including that it is for demonstration only.
Property Source As %String(MAXLEN = 300) [ Required ];

Index RangeIdx On (AnalyteCode, Unit, AgeGroup) [ Unique ];

Storage Default
{
<Data name="RangeDefaultData">
<Value name="1">
<Value>AnalyteCode</Value>
</Value>
<Value name="2">
<Value>Unit</Value>
</Value>
<Value name="3">
<Value>AgeGroup</Value>
</Value>
<Value name="4">
<Value>CriticalLow</Value>
</Value>
<Value name="5">
<Value>CriticalHigh</Value>
</Value>
<Value name="6">
<Value>FloorSeverity</Value>
</Value>
<Value name="7">
<Value>Source</Value>
</Value>
</Data>
<DataLocation>^Readback.Config.RangeD</DataLocation>
<DefaultData>RangeDefaultData</DefaultData>
<IdLocation>^Readback.Config.RangeD</IdLocation>
<IndexLocation>^Readback.Config.RangeI</IndexLocation>
<StreamLocation>^Readback.Config.RangeS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
