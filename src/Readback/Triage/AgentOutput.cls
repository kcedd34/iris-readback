/// The agent's answer after strict validation, or the reason it cannot be used.
/// Parse() fills one of these from the raw answer text.
Class Readback.Triage.AgentOutput Extends %RegisteredObject
{

/// True only when every schema rule holds.
Property Valid As %Boolean [ InitialExpression = 0 ];

/// CRITICAL, RECOLLECT, NEEDS_REVIEW or NON_CRITICAL.
Property Decision As %String;

/// 0 to 3.
Property Severity As %Integer;

Property Rationale As %String(MAXLEN = 1000);

/// JSON array text of evidence identifiers.
Property Evidence As %String(MAXLEN = 1000);

/// low, medium or high.
Property Confidence As %String;

/// ok, not-from-tools or not-applicable: whether every evidence identifier was returned by a tool of this investigation.
Property EvidenceCheck As %String [ InitialExpression = "not-applicable" ];

/// Empty, or the formal refusal of the floor policy: what the agent answered and the floor it would have lowered.
Property PolicyRefusal As %String(MAXLEN = 300);

/// Empty when the answer is usable; otherwise one of schema-invalid, empty-or-refused, timeout,
/// provider-error, low-confidence, no-recorded-answer, tool-failure, tool-limit, evidence-not-from-tools,
/// floor-policy-refusal.
Property FailureKind As %String;

/// The literal reason for the failure.
Property FailureReason As %String(MAXLEN = 1000);

/// Strict parse of the answer text against the closed schema. Never throws.
ClassMethod Parse(pText As %String) As Readback.Triage.AgentOutput
{
	Set tOut = ##class(Readback.Triage.AgentOutput).%New()
	Set tText = $ZStrip(pText, "<>WC")
	If tText = "" {
		Quit ..Fail(tOut, "empty-or-refused", "empty answer (refusal or no content)")
	}
	Set tParseError = ""
	Try {
		Set tObj = {}.%FromJSON(tText)
	} Catch ex {
		Set tParseError = ex.DisplayString()
	}
	If tParseError '= "" { Quit ..Fail(tOut, "schema-invalid", "answer is not valid JSON: "_tParseError) }
	If '$IsObject(tObj) || ('tObj.%IsA("%Library.DynamicObject")) {
		Quit ..Fail(tOut, "schema-invalid", "answer is not a JSON object")
	}
	Set tFields = ##class(Readback.Triage.Schema).Fields()
	Set tPtr = 0
	While $ListNext(tFields, tPtr, tField) {
		If 'tObj.%IsDefined(tField) { Quit }
	}
	If 'tObj.%IsDefined(tField) { Quit ..Fail(tOut, "schema-invalid", "missing field '"_tField_"'") }
	Set tIter = tObj.%GetIterator()
	While tIter.%GetNext(.tKey, .tVal) {
		If $ListFind(tFields, tKey) = 0 { Quit }
	}
	If $ListFind(tFields, tKey) = 0 { Quit ..Fail(tOut, "schema-invalid", "unexpected field '"_tKey_"'") }

	If tObj.%GetTypeOf("decision") '= "string" { Quit ..Fail(tOut, "schema-invalid", "decision must be a string") }
	If $ListFind(##class(Readback.Triage.Schema).Decisions(), tObj.decision) = 0 {
		Quit ..Fail(tOut, "schema-invalid", "decision '"_tObj.decision_"' is not one of CRITICAL, RECOLLECT, NEEDS_REVIEW, NON_CRITICAL")
	}
	If tObj.%GetTypeOf("severity") '= "number" { Quit ..Fail(tOut, "schema-invalid", "severity must be an integer from 0 to 3") }
	Set tSeverity = tObj.severity
	If (tSeverity # 1 '= 0) || (tSeverity < 0) || (tSeverity > 3) {
		Quit ..Fail(tOut, "schema-invalid", "severity "_tSeverity_" is not an integer from 0 to 3")
	}
	If tObj.%GetTypeOf("rationale") '= "string" { Quit ..Fail(tOut, "schema-invalid", "rationale must be a string") }
	If $Length(tObj.rationale) > ##class(Readback.Triage.Schema).#RationaleMaxLength {
		Quit ..Fail(tOut, "schema-invalid", "rationale has "_$Length(tObj.rationale)_" characters, the limit is "_##class(Readback.Triage.Schema).#RationaleMaxLength)
	}
	If tObj.%GetTypeOf("evidence") '= "array" { Quit ..Fail(tOut, "schema-invalid", "evidence must be a list") }
	Set tBadItem = 0
	For i = 0:1:tObj.evidence.%Size()-1 {
		If (tBadItem = 0) && (tObj.evidence.%GetTypeOf(i) '= "string") { Set tBadItem = i + 1 }
	}
	If tBadItem { Quit ..Fail(tOut, "schema-invalid", "evidence item "_tBadItem_" is not text") }
	If tObj.%GetTypeOf("confidence") '= "string" { Quit ..Fail(tOut, "schema-invalid", "confidence must be a string") }
	If $ListFind(##class(Readback.Triage.Schema).Confidences(), tObj.confidence) = 0 {
		Quit ..Fail(tOut, "schema-invalid", "confidence '"_tObj.confidence_"' is not one of low, medium, high")
	}
	Set tOut.Valid = 1
	Set tOut.Decision = tObj.decision, tOut.Severity = tSeverity, tOut.Rationale = tObj.rationale
	Set tOut.Evidence = tObj.evidence.%ToJSON(), tOut.Confidence = tObj.confidence
	If tOut.Confidence = "low" {
		Set tOut.FailureKind = "low-confidence", tOut.FailureReason = "agent confidence low"
	}
	Quit tOut
}

ClassMethod Fail(pOut As Readback.Triage.AgentOutput, pKind As %String, pReason As %String) As Readback.Triage.AgentOutput [ Private ]
{
	Set pOut.Valid = 0, pOut.FailureKind = pKind, pOut.FailureReason = pReason
	Quit pOut
}

}
