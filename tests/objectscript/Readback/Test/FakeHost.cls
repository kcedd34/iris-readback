/// A stand-in for a business host in the trace tests: records what was sent, or fails the way a disabled target does,
/// or raises.
Class Readback.Test.FakeHost Extends %RegisteredObject
{

/// ok, error or raise.
Property Behaviour As %String [ InitialExpression = "ok" ];

Property Sent As %DynamicArray;

Method %OnNew(pBehaviour As %String = "ok") As %Status
{
	Set ..Behaviour = pBehaviour, ..Sent = []
	Quit $$$OK
}

Method SendRequestAsync(pTarget As %String, pRequest As %Persistent, pDescription As %String = "") As %Status
{
	If ..Behaviour = "raise" { Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "the host raised")) }
	If ..Behaviour = "error" { Quit $$$ERROR($$$GeneralError, "the target is disabled") }
	Do ..Sent.%Push({"target":(pTarget),"seq":(pRequest.Seq),"tool":(pRequest.Tool),"status":(pRequest.Status),"mode":(pRequest.Mode),"arguments":(pRequest.Arguments),"summary":(pRequest.Summary),"durationMs":(pRequest.DurationMs)})
	Quit $$$OK
}

}
