/// Business operation that only logs each lab result. No agent and no rules yet.
Class Readback.Outbound.LogOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnLabResult(pRequest As Readback.Msg.LabResult, Output pResponse As Ens.Response) As %Status
{
	$$$LOGINFO("Lab result "_pRequest.MessageControlId_" patient="_pRequest.PatientId_" analyte="_pRequest.AnalyteCode_" value="_pRequest.ValueText_" "_pRequest.Unit_" source="_pRequest.Source)
	Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Readback.Msg.LabResult">
    <Method>OnLabResult</Method>
  </MapItem>
</MapItems>
}

}
