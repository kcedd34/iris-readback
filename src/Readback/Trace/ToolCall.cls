/// One tool call of an agent investigation, in the order the agent made it. The ordered calls are what replay shows
/// and what lets a decision be rebuilt including the path of its investigation.
Class Readback.Trace.ToolCall Extends %Persistent
{

Property Decision As Readback.Trace.Decision [ Required ];

/// 1, 2, 3 ... in the order the agent made the calls.
Property Seq As %Integer [ Required ];

/// One of the four tool names, or the name the agent asked for when there is no such tool.
Property Tool As %String(MAXLEN = 50);

/// The arguments as the agent sent them. No identifier is a legal argument.
Property ArgumentsJson As %String(MAXLEN = "");

/// The result handed to the agent, bounded to the size the configuration allows.
Property ResultJson As %String(MAXLEN = "");

/// ok, refused (a policy denied it), failed (it ran and failed, or no result came back) or unknown-tool.
Property Status As %String(VALUELIST = ",ok,refused,failed,unknown-tool");

/// Empty for ok; the denial or error text otherwise, redacted.
Property Reason As %String(MAXLEN = 500);

Property DurationMs As %Integer;

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

Index DecisionSeq On (Decision, Seq) [ Unique ];

}
