/// The floor policy, attached to the agent step: a result critical by rule or by change is never lowered. It is stated
/// here as data and checked on the agent's answer before the composition runs, so a lowering answer is refused formally
/// and the refusal is recorded with the case. The composition `max(floor, agent)` does not depend on this class: with the
/// policy switched off the composition alone still keeps the critical. The platform's own policies see tool calls only and
/// nothing hooks the final answer, which is why this is a class of the product (docs/probes.md, Probe 15).
Class Readback.Governance.FloorPolicy
{

/// The floor severity from which the rule applies: a critical.
Parameter CriticalFloor = 3;

/// When 0 the policy lets every answer through. Only the tests switch it off, to prove the composition alone holds.
ClassMethod Enabled() As %Boolean
{
	Quit '+$Get(^Readback("floorPolicyOff"))
}

/// The formal refusal text when the answer would lower a critical floor, else "". A usable answer lowers a critical when
/// its severity is below the floor or its decision is not CRITICAL. An answer that is not usable is not judged here: the
/// composition does not use it either.
ClassMethod Review(pFloor As Readback.Triage.FloorResult, pAgent As Readback.Triage.AgentOutput) As %String
{
	Quit:'..Enabled() ""
	Quit:'$IsObject(pAgent) ""
	Quit:'pAgent.Valid ""
	Quit:pFloor.Severity<..#CriticalFloor ""
	Set tLowers = (pAgent.Severity < pFloor.Severity) || (pAgent.Decision '= "CRITICAL")
	Quit:'tLowers ""
	Quit "refused: the agent answered "_pAgent.Decision_" with severity "_pAgent.Severity_" on a result the floor holds at "_pFloor.Severity_" ("_$Select(pFloor.DeltaTriggered:"critical by change", 1:"critical by rule")_")"
}

}
