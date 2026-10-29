/// One change rule: how far a result may move from an earlier result of the same patient and analyte, inside a
/// window, before the floor is raised. Loaded from data/config/delta-rules.json. Demonstration values only.
Class Readback.Config.DeltaRule Extends %Persistent
{

Property AnalyteCode As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

/// The reference unit of the analyte: the change is measured in this unit.
Property Unit As %String(COLLATION = "EXACT", MAXLEN = 50) [ Required ];

/// A change of more than this, in Unit, raises the floor.
Property MaxChange As %Numeric(MINVAL = 0.000001, SCALE = 4) [ Required ];

/// Only earlier results collected at most this many hours before count.
Property WindowHours As %Integer(MINVAL = 1) [ Required ];

Property Direction As %String(VALUELIST = ",fall,rise,either") [ Required ];

/// Severity assigned by the rule, 0 to 3.
Property FloorSeverity As %Integer(MAXVAL = 3, MINVAL = 0) [ Required ];

Property Source As %String(MAXLEN = 300) [ Required ];

Index AnalyteIdx On AnalyteCode [ Unique ];

Storage Default
{
<Data name="DeltaRuleDefaultData">
<Value name="1">
<Value>AnalyteCode</Value>
</Value>
<Value name="2">
<Value>Unit</Value>
</Value>
<Value name="3">
<Value>MaxChange</Value>
</Value>
<Value name="4">
<Value>WindowHours</Value>
</Value>
<Value name="5">
<Value>Direction</Value>
</Value>
<Value name="6">
<Value>FloorSeverity</Value>
</Value>
<Value name="7">
<Value>Source</Value>
</Value>
</Data>
<DataLocation>^Readback.Config.DeltaRuleD</DataLocation>
<DefaultData>DeltaRuleDefaultData</DefaultData>
<IdLocation>^Readback.Config.DeltaRuleD</IdLocation>
<IndexLocation>^Readback.Config.DeltaRuleI</IndexLocation>
<StreamLocation>^Readback.Config.DeltaRuleS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
