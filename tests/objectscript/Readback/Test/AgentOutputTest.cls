/// Strict validation of the agent's answer text against the closed decision schema.
Class Readback.Test.AgentOutputTest Extends %UnitTest.TestCase
{

ClassMethod Valid(pChange As %String = "") As %String
{
	Set tObj = {"decision":"CRITICAL","severity":3,"rationale":"Above the critical limit.","evidence":["current-result"],"confidence":"high"}
	Quit tObj.%ToJSON()
}

ClassMethod Without(pField As %String) As %String
{
	Set tObj = {}.%FromJSON(..Valid())
	Do tObj.%Remove(pField)
	Quit tObj.%ToJSON()
}

ClassMethod With(pField As %String, pValue) As %String
{
	Set tObj = {}.%FromJSON(..Valid())
	Do tObj.%Set(pField, pValue)
	Quit tObj.%ToJSON()
}

Method AssertInvalid(pText As %String, pFragment As %String, pLabel As %String)
{
	Set tOut = ##class(Readback.Triage.AgentOutput).Parse(pText)
	Do $$$AssertEquals(tOut.Valid, 0, pLabel_": not valid")
	Do $$$AssertEquals(tOut.FailureKind, "schema-invalid", pLabel_": kind is schema-invalid")
	Do $$$AssertTrue(tOut.FailureReason[pFragment, pLabel_": reason names the problem ("_tOut.FailureReason_")")
}

Method TestValidAnswer()
{
	Set tOut = ##class(Readback.Triage.AgentOutput).Parse(..Valid())
	Do $$$AssertEquals(tOut.Valid, 1, "a valid answer parses")
	Do $$$AssertEquals(tOut.FailureKind, "", "no failure kind")
	Do $$$AssertEquals(tOut.Decision, "CRITICAL", "decision kept")
	Do $$$AssertEquals(tOut.Severity, 3, "severity kept")
	Do $$$AssertEquals(tOut.Rationale, "Above the critical limit.", "rationale kept exactly")
	Do $$$AssertEquals(tOut.Evidence, "[""current-result""]", "evidence kept")
	Do $$$AssertEquals(tOut.Confidence, "high", "confidence kept")
}

Method TestEveryFieldIsRequired()
{
	For tField = "decision", "severity", "rationale", "evidence", "confidence" {
		Do ..AssertInvalid(..Without(tField), "missing field '"_tField_"'", "without "_tField)
	}
}

Method TestExtraFieldIsRejected()
{
	Do ..AssertInvalid(..With("notes", "extra"), "unexpected field 'notes'", "extra field")
}

Method TestDecisionMustBeOneOfFour()
{
	Do ..AssertInvalid(..With("decision", "MAYBE"), "decision 'MAYBE'", "unknown decision")
	Do ..AssertInvalid(..With("decision", "critical"), "decision 'critical'", "lowercase decision")
	Do ..AssertInvalid(..With("decision", 3), "decision must be a string", "numeric decision")
	For tDecision = "CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL" {
		Do $$$AssertEquals(##class(Readback.Triage.AgentOutput).Parse(..With("decision", tDecision)).Valid, 1, tDecision_" is accepted")
	}
}

Method TestSeverityMustBeIntegerFromZeroToThree()
{
	Do ..AssertInvalid(..With("severity", -1), "severity -1", "negative severity")
	Do ..AssertInvalid(..With("severity", 4), "severity 4", "severity above 3")
	Do ..AssertInvalid(..With("severity", 2.5), "severity 2.5", "fractional severity")
	Do ..AssertInvalid(..With("severity", "high"), "severity must be an integer", "text severity")
	For tSev = 0:1:3 {
		Do $$$AssertEquals(##class(Readback.Triage.AgentOutput).Parse(..With("severity", tSev)).Valid, 1, "severity "_tSev_" is accepted")
	}
}

Method TestRationaleLimit()
{
	Set tLong = $Justify("", 401)
	Set tLong = $Translate(tLong, " ", "x")
	Set tAtLimit = $Translate($Justify("", 400), " ", "x")
	Do ..AssertInvalid(..With("rationale", tLong), "401 characters", "401 characters")
	Do $$$AssertEquals(##class(Readback.Triage.AgentOutput).Parse(..With("rationale", tAtLimit)).Valid, 1, "400 characters are accepted")
	Do ..AssertInvalid(..With("rationale", 5), "rationale must be a string", "numeric rationale")
}

Method TestEvidenceMustBeAListOfText()
{
	Do ..AssertInvalid(..With("evidence", "current-result"), "evidence must be a list", "text evidence")
	Do ..AssertInvalid(..With("evidence", [1,2]), "evidence item 1", "numeric items")
	Do $$$AssertEquals(##class(Readback.Triage.AgentOutput).Parse(..With("evidence", [])).Valid, 1, "an empty list is accepted")
}

Method TestConfidenceMustBeOneOfThree()
{
	Do ..AssertInvalid(..With("confidence", "certain"), "confidence 'certain'", "unknown confidence")
}

Method TestLowConfidenceIsAValidAnswerWithAFailureKind()
{
	Set tOut = ##class(Readback.Triage.AgentOutput).Parse(..With("confidence", "low"))
	Do $$$AssertEquals(tOut.Valid, 1, "the answer itself is valid")
	Do $$$AssertEquals(tOut.FailureKind, "low-confidence", "kind is low-confidence")
	Do $$$AssertEquals(tOut.FailureReason, "agent confidence low", "literal reason")
}

Method TestNotJsonAndNotAnObject()
{
	Do ..AssertInvalid("this is not json", "not valid JSON", "plain text")
	Do ..AssertInvalid("[1,2,3]", "not a JSON object", "a JSON list")
	Do ..AssertInvalid("{""decision"":", "not valid JSON", "truncated JSON")
}

Method TestEmptyAndWhitespaceAreEmptyOrRefused()
{
	For tText = "", "   ", $Char(9)_$Char(10) {
		Set tOut = ##class(Readback.Triage.AgentOutput).Parse(tText)
		Do $$$AssertEquals(tOut.FailureKind, "empty-or-refused", "empty text has kind empty-or-refused")
		Do $$$AssertEquals(tOut.FailureReason, "empty answer (refusal or no content)", "literal reason")
		Do $$$AssertEquals(tOut.Valid, 0, "not valid")
	}
}

}
