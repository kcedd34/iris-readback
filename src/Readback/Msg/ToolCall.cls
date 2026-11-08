/// One tool call of an agent investigation, sent to the tool trace operation so that it shows as a step of the session in
/// the Visual Trace. It carries the tool, a summary of the arguments (never an identifier of a patient), the status, the time
/// and a one-line summary of the answer; the full arguments and result live in the trace table of the product.
Class Readback.Msg.ToolCall Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 50);

Property Seq As %Integer;

Property Tool As %String(MAXLEN = 50);

/// ok, refused or failed.
Property Status As %String(MAXLEN = 20);

Property DurationMs As %Integer;

/// live for a call the agent made, replay for a call read from a recorded investigation.
Property Mode As %String(MAXLEN = 10);

Property Arguments As %String(MAXLEN = 150);

Property Summary As %String(MAXLEN = 200);

}
