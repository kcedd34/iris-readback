/// Receives one message per tool call so that each call shows as a step of the session in the visual trace.
/// It does nothing else.
Class Readback.Agent.ToolHost Extends Ens.BusinessOperation
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
