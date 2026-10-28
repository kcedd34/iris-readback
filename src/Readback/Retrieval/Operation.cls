/// Business operation that owns the retrieval engine (one process, one copy of the embedding model).
/// It answers every request; a failure is an answer with Available false, never an exception.
Class Readback.Retrieval.Operation Extends Ens.BusinessOperation
{

Property Engine As Readback.Retrieval.Engine;

Parameter INVOCATION = "Queue";

Method OnInit() As %Status
{
	Set ..Engine = ##class(Readback.Retrieval.Engine).%New()
	Do ..Engine.Build()
	If ..Engine.Available { $$$LOGINFO("Retrieval engine ready: index "_..Engine.IndexVersion) } Else { $$$LOGWARNING("Retrieval is not available: "_..Engine.Reason) }
	Quit $$$OK
}

Method OnSearch(pRequest As Readback.Msg.RetrievalRequest, Output pResponse As Readback.Msg.RetrievalResponse) As %Status
{
	Set pResponse = ..Engine.Search(pRequest)
	Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Readback.Msg.RetrievalRequest">
    <Method>OnSearch</Method>
  </MapItem>
</MapItems>
}

}
