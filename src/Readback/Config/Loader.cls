/// Loads the configuration tables and the replay recordings from the JSON files under data/.
Class Readback.Config.Loader
{

/// Reloads ranges, prices and recordings. pCounts(name) holds the number of rows loaded.
ClassMethod LoadAll(pDir As %String = "", Output pCounts) As %Status
{
	Kill pCounts
	Set:pDir="" pDir=##class(Readback.Config.Paths).Data()
	Set tSC = ..LoadAnalytes(pDir_"/config/analytes.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("analytes") = tN
	Set tSC = ..LoadRanges(pDir_"/config/critical-ranges.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("ranges") = tN
	Set tSC = ..LoadDeltaRules(pDir_"/config/delta-rules.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("deltaRules") = tN
	Set tSC = ..LoadPrices(pDir_"/config/price-table.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("prices") = tN
	Set tSC = ..LoadBudget(pDir_"/config/budget.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("budget") = tN
	// The bounds of the agent investigation. Not loaded means no agent call is made (Readback.Config.AgentTools.Current).
	If ##class(%File).Exists(pDir_"/config/agent-tools.json") {
		Set tSC = ..LoadAgentTools(pDir_"/config/agent-tools.json", .tN)
		Quit:$$$ISERR(tSC) tSC
		Set pCounts("agentTools") = tN
	}
	// The escalation list is an addition to the read-back task: a file that is not valid is reported and the product goes on.
	If ##class(%File).Exists(pDir_"/config/escalation.json") {
		Set tEsc = ##class(Readback.Notify.Escalation).Load(pDir_"/config/escalation.json")
		If $$$ISERR(tEsc) { Do ##class(%SYS.System).WriteToConsoleLog("Readback: "_$System.Status.GetErrorText(tEsc)_"; no alert will be raised for a critical result", 0, 1) }
		Set pCounts("escalation") = $Select($$$ISOK(tEsc):##class(Readback.Notify.Escalation).Levels(), 1:0)
	}
	If ##class(%File).Exists(pDir_"/replay/recordings.jsonl") {
		Set tSC = ##class(Readback.Replay.Recording).LoadFile(pDir_"/replay/recordings.jsonl", .tN, 1)
		Quit:$$$ISERR(tSC) tSC
		Set pCounts("recordings") = tN
	}
	Quit $$$OK
}

/// Reloads everything when the hash of the data files, given by the caller, differs from the stored one.
ClassMethod LoadIfChanged(pHash As %String, pDir As %String = "") As %Status
{
	Set:pDir="" pDir=##class(Readback.Config.Paths).Data()
	Quit:$Get(^Readback("dataHash"))=pHash $$$OK
	Set tSC = ..LoadAll(pDir, .tCounts)
	Set:$$$ISOK(tSC) ^Readback("dataHash") = pHash
	Quit tSC
}

ClassMethod ReadJSON(pFile As %String, Output pObject) As %Status
{
	Set pObject = ""
	Quit:'##class(%File).Exists(pFile) $$$ERROR($$$GeneralError, "Configuration file not found: "_pFile)
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set pObject = {}.%FromJSON(tStream)
	} Catch ex {
		Set tSC = $$$ERROR($$$GeneralError, "Configuration file "_pFile_" is not valid JSON: "_ex.DisplayString())
	}
	Quit tSC
}

ClassMethod LoadRanges(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	Set tRows = tDoc.ranges
	If '$IsObject(tRows) Quit $$$ERROR($$$GeneralError, "Range table has no 'ranges' list")
	Set tAges = ",neonate,child,adult,"
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i), tNo = i + 1, tMissing = ""
		For tField = "analyteCode", "unit", "ageGroup", "floorSeverity", "source" {
			Set:(tRow.%Get(tField)="")&&(tMissing="") tMissing = tField
		}
		If tMissing '= "" { Set tSC = $$$ERROR($$$GeneralError, "Range row "_tNo_" is missing required field '"_tMissing_"'")  Quit }
		If tAges '[ (","_tRow.ageGroup_",") { Set tSC = $$$ERROR($$$GeneralError, "Range row "_tNo_" has an invalid ageGroup '"_tRow.ageGroup_"'")  Quit }
		If (tRow.criticalLow = "") && (tRow.criticalHigh = "") { Set tSC = $$$ERROR($$$GeneralError, "Range row "_tNo_" needs criticalLow or criticalHigh")  Quit }
		If (tRow.floorSeverity < 0) || (tRow.floorSeverity > 3) { Set tSC = $$$ERROR($$$GeneralError, "Range row "_tNo_" has floorSeverity outside 0 to 3")  Quit }
		If ##class(Readback.Config.Analyte).CodeIdxExists(tRow.analyteCode, .tAnalyteId) {
			Set tAnalyte = ##class(Readback.Config.Analyte).%OpenId(tAnalyteId)
			If tAnalyte.ReferenceUnit '= tRow.unit { Set tSC = $$$ERROR($$$GeneralError, "Range row "_tNo_" uses unit '"_tRow.unit_"' but the reference unit of analyte "_tRow.analyteCode_" is '"_tAnalyte.ReferenceUnit_"'")  Quit }
		}
	}
	If $$$ISERR(tSC) Quit tSC
	TStart
	Do ##class(Readback.Config.Range).%KillExtent()
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Set tRange = ##class(Readback.Config.Range).%New()
		Set tRange.AnalyteCode = tRow.analyteCode
		Set tRange.Unit = tRow.unit
		Set tRange.AgeGroup = tRow.ageGroup
		Set tRange.CriticalLow = tRow.criticalLow
		Set tRange.CriticalHigh = tRow.criticalHigh
		Set tRange.FloorSeverity = tRow.floorSeverity
		Set tRange.Source = tRow.source
		Set tSC = tRange.%Save()
		If $$$ISERR(tSC) { TRollback  Quit }
		Set pCount = pCount + 1
	}
	If $$$ISOK(tSC) { TCommit }
	Quit tSC
}

/// Loads the change rules. Every rule uses the reference unit of its analyte, so a change is always measured in it.
ClassMethod LoadDeltaRules(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	Set tRows = tDoc.rules
	If '$IsObject(tRows) Quit $$$ERROR($$$GeneralError, "Change rule table has no 'rules' list")
	Set tSeen = ""
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i), tNo = i + 1
		Set tMissing = ""
		For tField = "analyteCode", "unit", "maxChange", "windowHours", "direction", "floorSeverity", "source" {
			If 'tRow.%IsDefined(tField) { Set tMissing = tField  Quit }
		}
		If tMissing '= "" { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" is missing required field '"_tMissing_"'")  Quit }
		If (tRow.%GetTypeOf("maxChange") '= "number") || (tRow.maxChange '> 0) { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" has a maxChange that is not a number greater than 0")  Quit }
		If (tRow.%GetTypeOf("windowHours") '= "number") || (tRow.windowHours < 1) || (tRow.windowHours '= (tRow.windowHours\1)) { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" has a windowHours that is not a whole number of at least 1")  Quit }
		If ",fall,rise,either," '[ (","_tRow.direction_",") { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" has an invalid direction '"_tRow.direction_"'")  Quit }
		If (tRow.floorSeverity < 0) || (tRow.floorSeverity > 3) { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" has floorSeverity outside 0 to 3")  Quit }
		If tSeen [ (","_tRow.analyteCode_",") { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" repeats analyte "_tRow.analyteCode)  Quit }
		Set tSeen = tSeen_","_tRow.analyteCode_","
		If '##class(Readback.Config.Analyte).CodeIdxExists(tRow.analyteCode, .tAnalyteId) { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" names analyte "_tRow.analyteCode_", which is not in the analyte table")  Quit }
		If ##class(Readback.Config.Analyte).%OpenId(tAnalyteId).ReferenceUnit '= tRow.unit { Set tSC = $$$ERROR($$$GeneralError, "Change rule "_tNo_" uses unit '"_tRow.unit_"' but the reference unit of analyte "_tRow.analyteCode_" is '"_##class(Readback.Config.Analyte).%OpenId(tAnalyteId).ReferenceUnit_"'")  Quit }
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.DeltaRule).%KillExtent()
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Set tRule = ##class(Readback.Config.DeltaRule).%New()
		Set tRule.AnalyteCode = tRow.analyteCode, tRule.Unit = tRow.unit, tRule.MaxChange = tRow.maxChange, tRule.WindowHours = tRow.windowHours
		Set tRule.Direction = tRow.direction, tRule.FloorSeverity = tRow.floorSeverity, tRule.Source = tRow.source
		Set tSC = tRule.%Save()
		If $$$ISERR(tSC) { TRollback  Quit }
		Set pCount = pCount + 1
	}
	If $$$ISOK(tSC) { TCommit }
	Quit tSC
}

ClassMethod LoadAnalytes(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	Set tRows = tDoc.analytes
	If '$IsObject(tRows) Quit $$$ERROR($$$GeneralError, "Analyte table has no 'analytes' list")
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i), tNo = i + 1, tMissing = ""
		For tField = "analyteCode", "name", "referenceUnit" {
			Set:(tRow.%Get(tField)="")&&(tMissing="") tMissing = tField
		}
		If tMissing '= "" { Set tSC = $$$ERROR($$$GeneralError, "Analyte row "_tNo_" is missing required field '"_tMissing_"'")  Quit }
		If tRow.%IsDefined("molarMass") {
			If (tRow.%GetTypeOf("molarMass") '= "number") || (tRow.molarMass '> 0) { Set tSC = $$$ERROR($$$GeneralError, "Analyte row "_tNo_" has a molarMass that is not a number greater than 0")  Quit }
		}
		If tRow.%IsDefined("decimals") {
			If (tRow.%GetTypeOf("decimals") '= "number") || (tRow.decimals '? 1N) || (tRow.decimals > 4) { Set tSC = $$$ERROR($$$GeneralError, "Analyte row "_tNo_" has a decimals value that is not a whole number from 0 to 4")  Quit }
		}
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.Analyte).%KillExtent()
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Set tAnalyte = ##class(Readback.Config.Analyte).%New()
		Set tAnalyte.AnalyteCode = tRow.analyteCode, tAnalyte.Name = tRow.name, tAnalyte.ReferenceUnit = tRow.referenceUnit
		Set:tRow.%IsDefined("molarMass") tAnalyte.MolarMass = tRow.molarMass
		Set:tRow.%IsDefined("decimals") tAnalyte.Decimals = tRow.decimals
		Set tSC = tAnalyte.%Save()
		If $$$ISERR(tSC) { TRollback  Quit }
		Set pCount = pCount + 1
	}
	If $$$ISOK(tSC) { TCommit }
	Quit tSC
}

/// Loads the ceilings of the agent budget. Each must be a number greater than 0 (token ceilings also whole).
ClassMethod LoadBudget(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	For tField = "perResultTokens", "hourlyCostUsd", "hourlyTokens" {
		If (tDoc.%GetTypeOf(tField) '= "number") || (tDoc.%Get(tField) '> 0) { Set tSC = $$$ERROR($$$GeneralError, "Budget value '"_tField_"' must be a number greater than 0")  Quit }
		If (tField '= "hourlyCostUsd") && (tDoc.%Get(tField) # 1 '= 0) { Set tSC = $$$ERROR($$$GeneralError, "Budget value '"_tField_"' must be a whole number")  Quit }
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.Budget).%KillExtent()
	Set tBudget = ##class(Readback.Config.Budget).%New()
	Set tBudget.PerResultTokens = tDoc.perResultTokens, tBudget.HourlyCostUsd = tDoc.hourlyCostUsd, tBudget.HourlyTokens = tDoc.hourlyTokens
	Set tSC = tBudget.%Save()
	If $$$ISERR(tSC) { TRollback  Quit tSC }
	TCommit
	Set pCount = 1
	Quit $$$OK
}

/// Loads the bounds of the agent investigation. Each must be a whole number greater than 0.
ClassMethod LoadAgentTools(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	For tField = "maxIterations", "maxToolCalls", "toolResultMaxChars", "expectedRounds" {
		If (tDoc.%GetTypeOf(tField) '= "number") || (tDoc.%Get(tField) '> 0) || (tDoc.%Get(tField) # 1 '= 0) { Set tSC = $$$ERROR($$$GeneralError, "Agent bound '"_tField_"' must be a whole number greater than 0")  Quit }
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.AgentTools).%KillExtent()
	Set tRow = ##class(Readback.Config.AgentTools).%New()
	Set tRow.MaxIterations = tDoc.maxIterations, tRow.MaxToolCalls = tDoc.maxToolCalls, tRow.ToolResultMaxChars = tDoc.toolResultMaxChars
	Set tRow.ExpectedRounds = tDoc.expectedRounds
	Set tSC = tRow.%Save()
	If $$$ISERR(tSC) { TRollback  Quit tSC }
	TCommit
	Set pCount = 1
	Quit $$$OK
}

ClassMethod LoadPrices(pFile As %String, Output pCount As %Integer) As %Status
{
	Set pCount = 0
	Set tSC = ..ReadJSON(pFile, .tDoc)
	Quit:$$$ISERR(tSC) tSC
	Set tRows = tDoc.prices
	If '$IsObject(tRows) Quit $$$ERROR($$$GeneralError, "Price table has no 'prices' list")
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		If (tRow.model = "") || (tRow.priceDate = "") { Set tSC = $$$ERROR($$$GeneralError, "Price row "_(i + 1)_" needs model and priceDate")  Quit }
		If $ZDateH(tRow.priceDate, 3, , , , , , , "") = "" { Set tSC = $$$ERROR($$$GeneralError, "Price row "_(i + 1)_" has an invalid priceDate")  Quit }
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.Price).%KillExtent()
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Set tPrice = ##class(Readback.Config.Price).%New()
		Set tPrice.Model = tRow.model
		Set tPrice.InputPerMillion = $Select($IsObject(tRow.inputPerMillion):"", 1:tRow.inputPerMillion)
		Set tPrice.OutputPerMillion = $Select($IsObject(tRow.outputPerMillion):"", 1:tRow.outputPerMillion)
		Set tPrice.PriceDate = $ZDateH(tRow.priceDate, 3)
		Set tSC = tPrice.%Save()
		If $$$ISERR(tSC) { TRollback  Quit }
		Set pCount = pCount + 1
	}
	If $$$ISOK(tSC) { TCommit }
	Quit tSC
}

}
