/// The change tool of the ablation: the earlier values of the patient and the variation of this result against each, and
/// nothing of the change rule (no verdict, no limit, no window, no direction). It exists only for the paid round that measures the
/// agent without the rule's judgement (Readback.Eval.Control.UseNoVerdictDelta); the product never uses it.
Class Readback.Eval.NoVerdictImpl
{

ClassMethod DeltaValues() As %String
{
	If '##class(Readback.Tools.Binding).IsBound() { Throw ##class(%Exception.General).%New("ToolFailure", 5001, "Readback.Eval.NoVerdictImpl", "no case is bound to this call") }
	Set tPatient = ##class(Readback.Tools.Binding).Get("patientId"), tAnalyte = ##class(Readback.Tools.Binding).Get("analyteCode")
	Set tCollected = ##class(Readback.Tools.Binding).Get("collectedAt")
	Set tOriginal = ##class(Readback.Tools.Binding).Get("originalNumeric"), tUnit = ##class(Readback.Tools.Binding).Get("originalUnit")
	Set tEffective = ##class(Readback.Tools.Binding).Get("effectiveNumeric")
	Set tOut = {"id":"delta-assessment","unit":(##class(Readback.Tools.Binding).Get("effectiveUnit")),"earlier":[]}
	Set tNow = $ZDateTimeH(tCollected, 3, , , , , , , , "")
	If (tNow = "") || (tOriginal = "") || (tOriginal = 0) { Set tOut.note = "no comparison is possible" Quit tOut.%ToJSON() }
	Set tFactor = tEffective / tOriginal
	Set tRows = ##class(Readback.Triage.Context).EarlierRows(tPatient, tAnalyte, ##class(Readback.Tools.Binding).Get("caseId"), tCollected, 3)
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Continue:tRow.unit'=tUnit
		Set tThen = $ZDateTimeH(tRow.collectedAt, 3, , , , , , , , "")
		Continue:tThen=""
		Set tHours = +$Justify(((($Piece(tNow, ",", 1) - $Piece(tThen, ",", 1)) * 86400) + ($Piece(tNow, ",", 2) - $Piece(tThen, ",", 2))) / 3600, 0, 1)
		Do tOut.earlier.%Push({"value":(tRow.value),"collectedAt":(tRow.collectedAt),"hoursBefore":(tHours),"change":(+$Justify((tOriginal - tRow.value) * tFactor, 0, 4))})
	}
	Set:tOut.earlier.%Size()=0 tOut.note = "no earlier result in the same unit"
	Quit ##class(Readback.Tools.Impl).Bounded(tOut)
}

}
