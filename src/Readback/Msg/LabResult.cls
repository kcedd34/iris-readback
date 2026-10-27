/// Normalized, persisted form of one received HL7 ORU^R01 lab result.
/// Units are kept as received; unit conversion belongs to a later feature.
Class Readback.Msg.LabResult Extends Ens.Request
{

/// MSH-10, kept as received.
Property MessageControlId As %String(MAXLEN = 50) [ Required ];

/// PID-3, synthetic identifiers only.
Property PatientId As %String(MAXLEN = 50) [ Required ];

/// OBX-3 identifier of the analyte.
Property AnalyteCode As %String(MAXLEN = 50) [ Required ];

/// OBX-5 exactly as received.
Property ValueText As %String(MAXLEN = 200);

/// OBX-5 as a number when it parses as one.
Property ValueNumeric As %Numeric(SCALE = 4);

/// OBX-6, original unit.
Property Unit As %String(MAXLEN = 50);

/// OBX-7.
Property ReferenceRange As %String(MAXLEN = 50);

/// OBR-7 in ISO form.
Property CollectedAt As %TimeStamp;

/// Sample quality indices as code=value entries, for example HEMOLYSIS_INDEX=120.
Property SampleIndices As list Of %String(MAXLEN = 100);

/// The whole received message, always preserved.
Property RawHL7 As %String(MAXLEN = "");

/// Channel the message arrived on.
Property Source As %String(VALUELIST = ",file,tcp");

Storage Default
{
<Data name="LabResultDefaultData">
<Subscript>"LabResult"</Subscript>
<Value name="1">
<Value>MessageControlId</Value>
</Value>
<Value name="2">
<Value>PatientId</Value>
</Value>
<Value name="3">
<Value>AnalyteCode</Value>
</Value>
<Value name="4">
<Value>ValueText</Value>
</Value>
<Value name="5">
<Value>ValueNumeric</Value>
</Value>
<Value name="6">
<Value>Unit</Value>
</Value>
<Value name="7">
<Value>ReferenceRange</Value>
</Value>
<Value name="8">
<Value>CollectedAt</Value>
</Value>
<Value name="9">
<Value>SampleIndices</Value>
</Value>
<Value name="10">
<Value>RawHL7</Value>
</Value>
<Value name="11">
<Value>Source</Value>
</Value>
</Data>
<DefaultData>LabResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
