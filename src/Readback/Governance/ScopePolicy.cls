/// The authorization policy of the agent's tool set: the second layer of the scope rule, behind the binding. The first layer
/// is that no tool takes a patient or case identifier and the server fixes the case before the session; this one checks every
/// call again, so that nothing outside the case, the tool set or the bounds is ever executed, by the policy itself and not by
/// the instructions to the agent. It fails closed: an error inside it denies the call.
/// Denial is returned as the platform's access-denied status; the model is handed the error and the product reads the refusal
/// from the session history and the audit entry.
Class Readback.Governance.ScopePolicy Extends %AI.Policy.Authorization
{

/// The only tools the agent may call.
Parameter Allowed = ",get_patient_history,get_delta_assessment,search_policy,get_sample_quality,";

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
	Set tReason = ""
	Try {
		Set tReason = ##class(Readback.Governance.ScopePolicy).Judge(call, metadata)
	} Catch ex {
		Do ##class(Readback.Governance.AuditPolicy).Fault(ex)
		Set tReason = "the policy failed, so the call is denied"
	}
	Quit:tReason'="" $$$ERROR($$$AICoreToolAccessDenied, tReason)
	Quit $$$OK
}

/// "" when the call may run, else the reason it may not. The first rule that fails wins.
ClassMethod Judge(pCall As %DynamicObject, pMetadata As %DynamicObject) As %String
{
	If '$IsObject(pCall) || '$IsObject(pMetadata) { Quit "the call could not be read" }
	If '##class(Readback.Tools.Binding).IsBound() { Quit "no case is bound to this call" }
	Set tName = pCall.name
	If ..#Allowed '[ (","_tName_",") { Quit "the tool is not in the tool set of this agent" }
	If pMetadata.ReadOnly '= "1" { Quit "only read-only tools may run" }
	Set tBounds = ##class(Readback.Config.AgentTools).Current()
	If '$IsObject(tBounds) { Quit "the agent bounds are not loaded" }
	Set tCalls = $Increment(^||Readback.ScopeCalls)
	If tCalls > tBounds.MaxToolCalls { Quit "the limit of "_tBounds.MaxToolCalls_" tool calls for one case is reached" }
	Quit ..ArgumentsReason(pCall.arguments)
}

/// A tool takes no identifier. An argument whose name says patient or case, or whose text looks like an identifier (letters
/// followed by digits, with or without a dash, such as SYN9000001 or RB2026-00034), is refused. The platform may hand the arguments as an
/// object or as JSON text.
ClassMethod ArgumentsReason(pArguments) As %String
{
	Quit:pArguments="" ""
	If '$IsObject(pArguments) {
		Set tText = pArguments, pArguments = ""
		Try { Set pArguments = {}.%FromJSON(tText) } Catch ex { Set pArguments = "" }
		If '$IsObject(pArguments) { Quit "the arguments could not be read" }
	}
	Set tBad = ""
	Set tIter = pArguments.%GetIterator()
	While tIter.%GetNext(.tKey, .tValue) {
		Set tLow = $ZConvert(tKey, "L")
		If (tLow [ "patient") || (tLow [ "case") || (tLow [ "subject") || (tLow [ "mrn") { Set tBad = tKey  Quit }
		If '$IsObject(tValue) && $Match(tValue, ".*[A-Za-z]{2,}[0-9]*[-_]?[0-9]{4,}.*") { Set tBad = tKey  Quit }
	}
	Quit $Select(tBad="":"", 1:"the call carries an identifier ("_tBad_"): no tool takes one, the case is fixed")
}

}
