/// Skeleton production: HL7 ORU^R01 in by file and TCP, normalize, persist, log.
Class Readback.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Readback.Production" LogGeneralTraceEvents="false">
  <Description>Skeleton: HL7 ORU^R01 in by file and TCP, normalized, persisted and logged.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Setting Target="Production" Name="AlertNotificationManager">Readback.Notify.Router</Setting>
  <Setting Target="Production" Name="AlertNotificationOperation">Readback.Notify.Pager</Setting>
  <Setting Target="Production" Name="AlertNotificationRecipients">communicator1</Setting>
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
    <Setting Target="Adapter" Name="JobPerConnection">1</Setting>
    <Setting Target="Host" Name="AckMode">App</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Readback.Triage</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>
  <Item Name="Readback.Triage" Category="" ClassName="Readback.Triage.Process" PoolSize="2" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AgentTimeoutSeconds">30</Setting>
  </Item>
  <Item Name="Readback.Agent" Category="" ClassName="Readback.Agent.Operation" PoolSize="2" Enabled="false" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ProviderName">openai</Setting>
    <Setting Target="Adapter" Name="ProviderConfig">{"api_key":"@{env:OPENAI_API_KEY}"}</Setting>
    <Setting Target="Adapter" Name="IrisTools">Readback.Tools.ToolSet</Setting>
    <Setting Target="Adapter" Name="Model">gpt-5.4</Setting>
    <Setting Target="Adapter" Name="SystemPrompt">You are a laboratory triage assistant for critical results. You receive one lab result: its case id, the patient's age, the analyte, the value, the value in the reference unit when it was converted, the reference range and the collection time. Everything else you need you get by calling tools, and you decide which ones the case calls for. Request every tool you need together, as parallel calls in a single step, instead of one after another: each extra step sends the whole conversation again. get_patient_history gives the patient's earlier results of the same analyte (ids earlier-result-1, earlier-result-2 and so on). get_delta_assessment gives the change against those results with the verdict of the deterministic change rule (id delta-assessment). search_policy finds passages of the laboratory policy and similar confirmed cases for a short description that you write, without any identifier (a passage id is quoted as written, similar cases are similar-case-1 and so on). get_sample_quality gives the sample quality indices (ids sample-index-hemolysis and so on). No tool takes a patient or case identifier: the case is fixed. A deterministic rule table and the change rule run before you and set a minimum severity; your answer can only raise the severity above it and never lower it, so do not assume a result is safe because it looks normal in isolation: check the earlier results and the change. If a tool fails or is refused, say what you could and could not check and do not guess. Answer only with the JSON object required by the schema. decision: CRITICAL when the result needs urgent communication to a clinician; RECOLLECT when sample quality makes the result unreliable and a new sample is needed; NEEDS_REVIEW when you cannot decide and a person must look; NON_CRITICAL when no urgent communication is needed. severity: an integer from 0 (none) to 3 (critical). rationale: at most 400 characters, plain language, saying what you read that led to the answer. evidence: identifiers of what you used and nothing else: current-result for the value you were given, or an id that a tool gave you in this investigation, such as earlier-result-2, delta-assessment, sample-index-hemolysis, the identifier of a policy passage, or similar-case-1. Cite none that you did not use. Use the converted value when one is given. confidence: low, medium or high; use low when you are unsure. Never give treatment advice. The data is synthetic.</Setting>
    <Setting Target="Adapter" Name="SessionConfigString">{"temperature":0,"extra_params":{"max_completion_tokens":400},"response_format":{"type":"json_schema","json_schema":{"name":"triage_decision","strict":true,"schema":{"type":"object","additionalProperties":false,"required":["decision","severity","rationale","evidence","confidence"],"properties":{"decision":{"type":"string","enum":["CRITICAL","RECOLLECT","NEEDS_REVIEW","NON_CRITICAL"]},"severity":{"type":"integer","enum":[0,1,2,3]},"rationale":{"type":"string"},"evidence":{"type":"array","items":{"type":"string"}},"confidence":{"type":"string","enum":["low","medium","high"]}}}}}}</Setting>
  </Item>
  <Item Name="Readback.Agent.ToolTrace" Category="" ClassName="Readback.Agent.ToolTrace" PoolSize="1" Enabled="true" Foreground="false" Comment="Receives one message per tool call (live and replay) so each call is a step of the decision session in the Visual Trace; it only records" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="Readback.Agent.Replay" Category="" ClassName="Readback.Agent.ReplayOperation" PoolSize="2" Enabled="true" Foreground="false" Comment="Recorded answers, used when no provider key is configured" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Retrieval" Category="" ClassName="Readback.Retrieval.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Policy and confirmed-case retrieval (local embeddings, no network at run time)" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Units" Category="" ClassName="Readback.Units.JavaOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Unit conversion with UCUM (Java, PEX)" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="%gatewayName">%Java Server</Setting>
    <Setting Target="Host" Name="%gatewayExtraClasspaths">/opt/readback/java/build/readback-units.jar:/opt/readback/java/lib/ucum-1.0.9.jar:/usr/irissys/dev/java/lib/1.8/intersystems-pex-1.0.0-shaded.jar</Setting>
  </Item>
  <Item Name="Readback.Communicators" Category="" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Read-back tasks for the communicating role" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Reviewers" Category="" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Human review tasks" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Outbound.OutcomeOperation" Category="" ClassName="Readback.Outbound.OutcomeOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Outbound.LogOperation" Category="" ClassName="Readback.Outbound.LogOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Ens.Alert" Category="" ClassName="Readback.Notify.Manager" PoolSize="1" Enabled="true" Foreground="false" Comment="The platform's alert manager: turns the alert of a critical result into a managed alert" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Readback.Notify.Router" Category="" ClassName="Ens.Alerting.NotificationManager" PoolSize="1" Enabled="true" Foreground="false" Comment="The platform's notification manager: the person to alert is the one of the alert's level" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="NotificationTransform">Readback.Notify.Transform</Setting>
  </Item>
  <Item Name="Readback.Notify.Monitor" Category="" ClassName="Readback.Notify.Monitor" PoolSize="1" Enabled="true" Foreground="false" Comment="The platform's overdue-alert monitor: escalation is the platform's" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="CallInterval">2</Setting>
    <Setting Target="Host" Name="OverdueAlertRule">Readback.Notify.OverdueRule</Setting>
  </Item>
  <Item Name="Readback.Notify.Pager" Category="" ClassName="Readback.Notify.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Delivery channel with its receipt: a simulated pager" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DeliveryMode">deliver</Setting>
  </Item>
</Production>
}

}
