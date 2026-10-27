/// Skeleton production: HL7 ORU^R01 in by file and TCP, normalize, persist, log.
Class Readback.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Readback.Production" LogGeneralTraceEvents="false">
  <Description>Skeleton: HL7 ORU^R01 in by file and TCP, normalized, persisted and logged.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Readback.Inbound.HL7File" Category="" ClassName="Readback.Inbound.HL7File" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/data/in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/data/archive</Setting>
    <Setting Target="Adapter" Name="WorkPath">/data/work</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Readback.Triage</Setting>
  </Item>
  <Item Name="Readback.Inbound.HL7TCP" Category="" ClassName="Readback.Inbound.HL7TCP" PoolSize="4" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Port">5001</Setting>
    <Setting Target="Host" Name="AckMode">App</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Readback.Triage</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>
  <Item Name="Readback.Triage" Category="" ClassName="Readback.Triage.Process" PoolSize="2" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentTimeoutSeconds">30</Setting>
  </Item>
  <Item Name="Readback.Agent" Category="" ClassName="EnsLib.AI.Agent.PassthroughOperation" PoolSize="2" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ProviderName">openai</Setting>
    <Setting Target="Adapter" Name="ProviderConfig">{"api_key":"@{env:OPENAI_API_KEY}"}</Setting>
    <Setting Target="Adapter" Name="Model">gpt-5.4</Setting>
    <Setting Target="Adapter" Name="SystemPrompt">You are a laboratory triage assistant for critical results. You receive one lab result with its unit, reference range, sample quality indices and the patient's earlier results for the same analyte. Decide whether the result needs urgent communication. Answer only with the JSON object required by the schema. decision: CRITICAL when the result needs urgent communication to a clinician; RECOLLECT when sample quality makes the result unreliable and a new sample is needed; NEEDS_REVIEW when you cannot decide and a person must look; NON_CRITICAL when no urgent communication is needed. severity: an integer from 0 (none) to 3 (critical). rationale: at most 400 characters, plain language, citing the earlier result or the sample index when you used it. evidence: identifiers of what you used, such as current-result, earlier-result-1, earlier-result-2, earlier-result-3 or sample-index-hemolysis. confidence: low, medium or high; use low when you are unsure. A deterministic rule table runs before you and your answer can only raise the severity above it, so do not assume a result is safe because it looks normal in isolation: compare it with the earlier results. Never give treatment advice. The data is synthetic.</Setting>
    <Setting Target="Adapter" Name="SessionConfigString">{"temperature":0,"max_tokens":400,"response_format":{"type":"json_schema","json_schema":{"name":"triage_decision","strict":true,"schema":{"type":"object","additionalProperties":false,"required":["decision","severity","rationale","evidence","confidence"],"properties":{"decision":{"type":"string","enum":["CRITICAL","RECOLLECT","NEEDS_REVIEW","NON_CRITICAL"]},"severity":{"type":"integer","enum":[0,1,2,3]},"rationale":{"type":"string"},"evidence":{"type":"array","items":{"type":"string"}},"confidence":{"type":"string","enum":["low","medium","high"]}}}}}}</Setting>
  </Item>
  <Item Name="Readback.Outbound.OutcomeOperation" Category="" ClassName="Readback.Outbound.OutcomeOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Outbound.LogOperation" Category="" ClassName="Readback.Outbound.LogOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
</Production>
}

}
