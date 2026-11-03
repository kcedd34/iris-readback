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

/// Decimals a value of this analyte is shown with in its reference unit (the clinical precision: glucose in mmol/L with one).
Property Decimals As %Integer(MAXVAL = 4, MINVAL = 0) [ InitialExpression = 1 ];

Index CodeIdx On AnalyteCode [ Unique ];

/// A value of an analyte rounded to its clinical precision, as text with its decimals (26.0, not 26). A value that is not a number,
/// or an analyte that is not in the table, comes back as it was given.
ClassMethod Round(pCode As %String, pValue As %String) As %String
{
	If (pValue = "") || '$IsValidNum(pValue) { Quit pValue }
	If '..CodeIdxExists(pCode, .tId) { Quit pValue }
	Set tDecimals = ..%OpenId(tId).Decimals
	Set tText = $FNumber(+pValue, "", tDecimals)
	Quit $Select($Extract(tText, 1) = ".":"0"_tText, $Extract(tText, 1, 2) = "-.":"-0"_$Extract(tText, 2, *), 1:tText)
}

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
<Value name="5">
<Value>Decimals</Value>
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
