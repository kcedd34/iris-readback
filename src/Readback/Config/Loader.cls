/// Loads the configuration tables and the replay recordings from the JSON files under data/.
Class Readback.Config.Loader
{

Parameter DATADIR = "/opt/readback/data";

/// Reloads ranges, prices and recordings. pCounts(name) holds the number of rows loaded.
ClassMethod LoadAll(pDir As %String = {..#DATADIR}, Output pCounts) As %Status
{
	Kill pCounts
	Set tSC = ..LoadAnalytes(pDir_"/config/analytes.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("analytes") = tN
	Set tSC = ..LoadRanges(pDir_"/config/critical-ranges.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("ranges") = tN
	Set tSC = ..LoadPrices(pDir_"/config/price-table.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("prices") = tN
	Set tSC = ..LoadBudget(pDir_"/config/budget.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("budget") = tN
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
ClassMethod LoadIfChanged(pHash As %String, pDir As %String = {..#DATADIR}) As %Status
{
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
	}
	Quit:$$$ISERR(tSC) tSC
	TStart
	Do ##class(Readback.Config.Analyte).%KillExtent()
	For i = 0:1:tRows.%Size()-1 {
		Set tRow = tRows.%Get(i)
		Set tAnalyte = ##class(Readback.Config.Analyte).%New()
		Set tAnalyte.AnalyteCode = tRow.analyteCode, tAnalyte.Name = tRow.name, tAnalyte.ReferenceUnit = tRow.referenceUnit
		Set:tRow.%IsDefined("molarMass") tAnalyte.MolarMass = tRow.molarMass
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
