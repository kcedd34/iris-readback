/// The plain sentences of the read-back task: the rule that made the result critical, with its value and its limit, and each piece
/// of evidence the agent cited, resolved to what the tool really returned. Built from the stored decision and its tool calls; the
/// identifiers stay beside the sentences so a person can still see what the agent wrote.
Class Readback.Trace.TaskText
{

/// The rules that raised the floor of this decision, as a list of sentences: the critical range with the value and the limit, and
/// the change rule with the change, the window and the limit. Empty when no rule did.
ClassMethod RuleLines(pTrace As Readback.Trace.Decision, pLab As Readback.Msg.LabResult, pAnalyte As %String) As %DynamicArray
{
	Set tLines = []
	Set tName = $ZConvert(pAnalyte, "L")
	Set tRuleId = pTrace.FloorRuleId
	If (tRuleId '= "") && (tRuleId '? 1"delta:".E) {
		Set tRange = ##class(Readback.Config.Range).%OpenId(tRuleId)
		If $IsObject(tRange) && ##class(Readback.Triage.Floor).IsCritical(..ValueIn(pTrace, pLab, tRange.Unit), tRange.%Id()) {
			Set tValue = ..ValueIn(pTrace, pLab, tRange.Unit)
			Set tWhere = " critical "_$Select((tRange.CriticalHigh'="")&&(tValue>=tRange.CriticalHigh):"high", 1:"low")_" limit, "_tRange.AgeGroup_" range"
			If (tRange.CriticalHigh '= "") && (tValue >= tRange.CriticalHigh) {
				Do tLines.%Push(+tValue_" "_tRange.Unit_" "_$Char(8805)_" "_+tRange.CriticalHigh_" "_tRange.Unit_", "_tName_tWhere)
			} Else {
				Do tLines.%Push(+tValue_" "_tRange.Unit_" "_$Char(8804)_" "_+tRange.CriticalLow_" "_tRange.Unit_", "_tName_tWhere)
			}
		}
	}
	Set tCollected = ##class(Readback.Triage.Context).CollectedOrNow(pLab)
	Set tEffective = $Select(pTrace.ConvertedValue'="":pTrace.ConvertedValue, 1:pLab.ValueNumeric)
	Set tEffectiveUnit = $Select(pTrace.ConvertedUnit'="":pTrace.ConvertedUnit, 1:pLab.Unit)
	Set tAssess = ##class(Readback.Triage.Delta).Assess(pLab.PatientId, pLab.AnalyteCode, pLab.MessageControlId, tCollected, pLab.ValueNumeric, pLab.Unit, tEffective, tEffectiveUnit)
	If tAssess.hit {
		Set tChange = $Select(tAssess.change<0:-tAssess.change, 1:tAssess.change)
		Set tVerb = $Case(tAssess.direction, "fall":"fell", "rise":"rose", :"changed")
		Do tLines.%Push(tName_" "_tVerb_" by "_tChange_" "_tAssess.unit_" within "_tAssess.windowHours_" hours, more than the "_+tAssess.limit_" "_tAssess.unit_" limit of the change rule")
	}
	Quit tLines
}

/// The value of the result in the unit of a range: as received when the unit is the same, else the converted value.
ClassMethod ValueIn(pTrace As Readback.Trace.Decision, pLab As Readback.Msg.LabResult, pUnit As %String) As %Numeric
{
	Quit:(pLab.Unit = pUnit) pLab.ValueNumeric
	Quit:(pTrace.ConvertedUnit = pUnit) && (pTrace.ConvertedValue '= "") pTrace.ConvertedValue
	Quit pLab.ValueNumeric
}

/// The cited identifiers as a list of {id, text}: text is what the tool returned for that identifier in this investigation, or
/// empty when nothing can be resolved (then the identifier is all there is to show).
ClassMethod Resolve(pTrace As Readback.Trace.Decision, pLab As Readback.Msg.LabResult, pIds As %DynamicArray) As %DynamicArray
{
	Set tOut = []
	Quit:'$IsObject(pIds) tOut
	Do ..Known(pTrace, pLab, .tText)
	Set tIter = pIds.%GetIterator()
	While tIter.%GetNext(.tKey, .tId) {
		Do tOut.%Push({"id":(tId),"text":($Get(tText(tId)))})
	}
	Quit tOut
}

/// Fills pText(id) with the sentence of every identifier the tools of this decision returned, and of current-result.
ClassMethod Known(pTrace As Readback.Trace.Decision, pLab As Readback.Msg.LabResult, ByRef pText)
{
	Set pText("current-result") = "Current result: "_pLab.ValueText_$Select(pLab.Unit'="":" "_pLab.Unit, 1:"")_$Select(pLab.CollectedAt'="":", collected "_pLab.CollectedAt, 1:"")
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, ResultJson FROM Readback_Trace.ToolCall WHERE Decision = ? AND Status = 'ok' ORDER BY Seq", pTrace.%Id())
	While tRS.%Next() {
		Set tTool = tRS.%Get("Tool"), tObj = ""
		Try { Set tObj = {}.%FromJSON(tRS.%Get("ResultJson")) } Catch ex { Set tObj = "" }
		Continue:'$IsObject(tObj)
		If tTool = "get_patient_history" {
			If $IsObject(tObj.earlier) {
				Set tI = tObj.earlier.%GetIterator()
				While tI.%GetNext(.tK, .tRow) { Set pText(tRow.id) = "Earlier result: "_tRow.value_" "_tRow.unit_", collected "_tRow.collectedAt }
			}
		} ElseIf tTool = "get_delta_assessment" {
			Set pText("delta-assessment") = ..DeltaSentence(tObj)
		} ElseIf tTool = "search_policy" {
			If $IsObject(tObj.passages) {
				Set tI = tObj.passages.%GetIterator()
				While tI.%GetNext(.tK, .tRow) {
					Set tTitle = ..PolicyTitle(tRow.id)
					Set pText(tRow.id) = "Policy passage: "_$Select(tTitle'="":tTitle, 1:$Extract(tRow.text, 1, 80))
				}
			}
			If $IsObject(tObj.similarCases) {
				Set tI = tObj.similarCases.%GetIterator()
				While tI.%GetNext(.tK, .tRow) { Set pText(tRow.id) = "Similar confirmed case, decided "_tRow.decision_" ("_tRow.route_")" }
			}
		} ElseIf tTool = "get_sample_quality" {
			If $IsObject(tObj.indices) {
				Set tI = tObj.indices.%GetIterator()
				While tI.%GetNext(.tK, .tRow) { Set pText(tRow.id) = "Sample quality: "_$ZConvert($Piece(tRow.code, "_INDEX", 1), "L")_" index "_tRow.value }
			}
		}
	}
}

ClassMethod DeltaSentence(pObj As %DynamicObject) As %String
{
	Quit:'pObj.comparable "Change against earlier results: "_pObj.floorVerdict_$Select(pObj.reason'="":" ("_pObj.reason_")", 1:"")
	Set tChange = $Select(pObj.change<0:-pObj.change, 1:pObj.change)
	Set tVerb = $Case(pObj.change<0, 1:"fell", :"rose")
	Quit "Change against earlier results: "_tVerb_" by "_tChange_" "_pObj.unit_" within "_pObj.windowHours_" hours, limit "_+pObj.limit_" "_pObj.unit_" ("_pObj.floorVerdict_")"
}

/// The title of a policy passage in the shipped policy file, or "".
ClassMethod PolicyTitle(pId As %String) As %String
{
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Quit:$System.Status.IsError(tStream.LinkToFile(##class(Readback.Retrieval.Policy).DefaultFile())) ""
	Set tTitle = ""
	While 'tStream.AtEnd {
		Set tLine = tStream.ReadLine()
		Continue:tLine=""
		Set tObj = ""
		Try { Set tObj = {}.%FromJSON(tLine) } Catch ex { Set tObj = "" }
		If $IsObject(tObj) && (tObj.id = pId) { Set tTitle = tObj.title  Quit }
	}
	Quit tTitle
}

}
