/// Composed outcome of a triage. Produced only by Readback.Triage.Composer.
Class Readback.Triage.FinalDecision Extends %RegisteredObject
{

Property Floor As %Integer;

/// Empty when the agent gave no valid answer.
Property AgentSeverity As %Integer;

Property AgentDecision As %String;

Property FinalSeverity As %Integer;

/// readback, review, recollect or release.
Property Route As %String;

Property Reason As %String(MAXLEN = 500);

/// Describes a disagreement between the floor and the agent, empty when there is none.
Property Divergence As %String(MAXLEN = 500);

}
