/// The tool set of the triage agent: four read-only tools. Each carries the read-only requirement, which the
/// authorization policy checks, with the scope rule. The audit policy is attached here, once, so each call is recorded once. The class
/// depends on the policy and on the tool methods because the platform generates its policy getter and its tool list
/// from the definition below when it compiles, and that fails silently when they are not compiled yet.
Class Readback.Tools.ToolSet Extends %AI.ToolSet [ DependsOn = (Readback.Governance.AuditPolicy, Readback.Governance.ScopePolicy, Readback.Tools.Impl) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="ReadbackTools">
  <Description>Read-only tools for investigating one laboratory result.</Description>
  <Policies>
    <Authorization Class="Readback.Governance.ScopePolicy"/>
    <Audit Class="Readback.Governance.AuditPolicy"/>
  </Policies>
  <Tool Name="get_patient_history" Class="Readback.Tools.Impl" Method="PatientHistory">
    <Description>Earlier results of this patient for the same analyte (newest first, within the last 7 days, at most 3). Takes no identifier: the case is fixed. Each earlier result has an id such as earlier-result-1 that you may cite as evidence.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="get_delta_assessment" Class="Readback.Tools.Impl" Method="DeltaAssessment">
    <Description>The change of this result against the patient's earlier results of the same analyte, with the verdict of the deterministic change rule (critical by change, no critical change, or not comparable). Takes no identifier. Cite it as delta-assessment.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="search_policy" Class="Readback.Tools.Impl" Method="SearchPolicy">
    <Description>Passages of the laboratory policy that fit a description, found by meaning, and similar cases already confirmed by a person. Pass a short description of the situation as query; do not include any identifier. Cite a passage by its id, a similar case as similar-case-N.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="get_sample_quality" Class="Readback.Tools.Impl" Method="SampleQuality">
    <Description>The sample quality indices of this result (hemolysis, lipemia, icterus). Takes no identifier. Each index has an id such as sample-index-hemolysis that you may cite as evidence.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
