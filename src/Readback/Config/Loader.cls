/// Loads the configuration tables and the replay recordings from the JSON files under data/.
Class Readback.Config.Loader
{

Parameter DATADIR = "/opt/readback/data";

/// Reloads ranges, prices and recordings. pCounts(name) holds the number of rows loaded.
ClassMethod LoadAll(pDir As %String = {..#DATADIR}, Output pCounts) As %Status
{
	Kill pCounts
	Set tSC = ..LoadRanges(pDir_"/config/critical-ranges.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("ranges") = tN
	Set tSC = ..LoadPrices(pDir_"/config/price-table.json", .tN)
	Quit:$$$ISERR(tSC) tSC
	Set pCounts("prices") = tN
	If ##class(%File).Exists(pDir_"/replay/recordings.jsonl") {
		Set tSC = ##class(Readback.Replay.Recording).LoadFile(pDir_"/replay/recordings.jsonl", .tN)
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
