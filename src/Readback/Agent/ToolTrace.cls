/// Receives one message per tool call of an agent investigation so that each call shows as a step of the decision's
/// session in the Visual Trace, in the live mode and, labelled "replay", in the replay mode. The message is the record:
/// this operation does nothing else, and nothing in the decision's path waits for it, reads it or depends on it.
Class Readback.Agent.ToolTrace Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnToolCall(pRequest As Readback.Msg.ToolCall, Output pResponse As Ens.Response) As %Status
{
	Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Readback.Msg.ToolCall">
    <Method>OnToolCall</Method>
  </MapItem>
</MapItems>
}

}
