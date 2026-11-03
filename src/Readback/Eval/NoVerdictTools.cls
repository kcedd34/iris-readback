/// The tool set of the product with one change: the change tool hands the agent the earlier values and the variation, not the
/// verdict of the change rule. Used only by the ablation round (Readback.Eval.Control.UseNoVerdictDelta). The other three tools are
/// the product's own and the tool keeps its name and its identifier, so the answers stay comparable.
Class Readback.Eval.NoVerdictTools Extends %AI.ToolSet [ DependsOn = (Readback.Governance.AuditPolicy, Readback.Governance.ScopePolicy, Readback.Tools.Impl, Readback.Eval.NoVerdictImpl) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="ReadbackToolsNoVerdict">
  <Description>Read-only tools for investigating one laboratory result.</Description>
  <Policies>
    <Authorization Class="Readback.Governance.ScopePolicy"/>
    <Audit Class="Readback.Governance.AuditPolicy"/>
  </Policies>
  <Tool Name="get_patient_history" Class="Readback.Tools.Impl" Method="PatientHistory">
    <Description>Earlier results of this patient for the same analyte (newest first, within the last 7 days, at most 3). Takes no identifier: the case is fixed. Each earlier result has an id such as earlier-result-1 that you may cite as evidence.</Description>
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="get_delta_assessment" Class="Readback.Eval.NoVerdictImpl" Method="DeltaValues">
    <Description>The earlier results of this patient for the same analyte with the change of this result against each of them (same unit, newest first, at most 3). It gives values and changes only, with no judgement of whether a change matters. Takes no identifier. Cite it as delta-assessment.</Description>
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
