/// The closed decision schema: one source for the parser and for the production settings.
/// The provider receives a schema that uses only keywords strict structured output is documented to accept
/// (an enum for the severity, no length limits); every constraint, including the 400-character rationale,
/// is enforced again by Readback.Triage.AgentOutput.Parse, whatever the provider claims to enforce.
Class Readback.Triage.Schema
{

Parameter RationaleMaxLength = 400;

ClassMethod Decisions() As %List
{
	Quit $ListBuild("CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL")
}

ClassMethod Confidences() As %List
{
	Quit $ListBuild("low", "medium", "high")
}

ClassMethod Fields() As %List
{
	Quit $ListBuild("decision", "severity", "rationale", "evidence", "confidence")
}

/// The JSON schema text sent to the provider.
ClassMethod SchemaJSON() As %String
{
	Quit "{""type"":""object"",""additionalProperties"":false,""required"":[""decision"",""severity"",""rationale"",""evidence"",""confidence""],""properties"":{""decision"":{""type"":""string"",""enum"":[""CRITICAL"",""RECOLLECT"",""NEEDS_REVIEW"",""NON_CRITICAL""]},""severity"":{""type"":""integer"",""enum"":[0,1,2,3]},""rationale"":{""type"":""string""},""evidence"":{""type"":""array"",""items"":{""type"":""string""}},""confidence"":{""type"":""string"",""enum"":[""low"",""medium"",""high""]}}}"
}

/// The longest answer the agent may give, in tokens: the max_tokens of the session configuration.
Parameter MaxTokens = 400;

/// The session configuration of the live agent item: strict structured output, deterministic, bounded.
ClassMethod SessionConfigJSON() As %String
{
	Quit "{""temperature"":0,""max_tokens"":"_..#MaxTokens_",""response_format"":{""type"":""json_schema"",""json_schema"":{""name"":""triage_decision"",""strict"":true,""schema"":"_..SchemaJSON()_"}}}"
}

}
