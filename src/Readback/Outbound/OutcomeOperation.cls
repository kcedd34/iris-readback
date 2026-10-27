/// Logs the outcome of each triage. Releases and recollect requests end here; review and read-back cases
/// also open a task (see Readback.Triage.Process).
Class Readback.Outbound.OutcomeOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnOutcome(pRequest As Readback.Msg.Outcome, Output pResponse As Ens.Response) As %Status
{
	$$$LOGINFO("Outcome "_pRequest.Route_" for "_pRequest.MessageControlId_" severity="_pRequest.FinalSeverity_" mode="_pRequest.Mode_": "_pRequest.Reason)
	Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Readback.Msg.Outcome">
    <Method>OnOutcome</Method>
  </MapItem>
</MapItems>
}

}
