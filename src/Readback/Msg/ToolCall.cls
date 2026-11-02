/// One tool call of an agent investigation, sent to the tool host so that it shows as a step of the session in the
/// visual trace. The full arguments and result live in the trace table of the product.
Class Readback.Msg.ToolCall Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 50);

Property Seq As %Integer;

Property Tool As %String(MAXLEN = 50);

/// ok, refused or failed.
Property Status As %String(MAXLEN = 20);

Property DurationMs As %Integer;

Property Summary As %String(MAXLEN = 200);

}
