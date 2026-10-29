/// Outcome of the deterministic range check.
Class Readback.Triage.FloorResult Extends %RegisteredObject
{

/// 0 to 3. 3 means critical by rule.
Property Severity As %Integer [ InitialExpression = 0 ];

/// Identifier of the range row that matched, empty when none applied.
Property RuleId As %String;

/// Why no rule applied, or which assumption was made (for example "age unknown, adult range used").
Property Note As %String(MAXLEN = 300);

/// True when the unit is not in the rule table for this analyte.
Property UnitUnknown As %Boolean [ InitialExpression = 0 ];

/// True when a change from the patient's earlier results met the change rule of the analyte (whether or not the
/// value limits were critical as well).
Property DeltaTriggered As %Boolean [ InitialExpression = 0 ];

}
