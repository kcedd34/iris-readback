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
    <Setting Target="Host" Name="TargetConfigNames">Readback.Outbound.LogOperation</Setting>
  </Item>
  <Item Name="Readback.Inbound.HL7TCP" Category="" ClassName="Readback.Inbound.HL7TCP" PoolSize="4" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Port">5001</Setting>
    <Setting Target="Host" Name="AckMode">App</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Readback.Outbound.LogOperation</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>
  <Item Name="Readback.Outbound.LogOperation" Category="" ClassName="Readback.Outbound.LogOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
</Production>
}

}
