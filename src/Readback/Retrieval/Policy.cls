/// The laboratory policy passages: reads and validates data/policy/passages.jsonl, computes the index version
/// (the hash of the file) and keeps the policy vector table in step with the file.
Class Readback.Retrieval.Policy
{

Parameter File = "/opt/readback/data/policy/passages.jsonl";

/// Reads the file into pPassages (a %DynamicArray of {id, source, title, text}) and returns the version.
/// A line that is not valid, lacks a field or repeats an id is an error naming the line.
ClassMethod Read(pFile As %String = {..#File}, Output pPassages As %DynamicArray, Output pVersion As %String) As %Status
{
	Set pPassages = [], pVersion = ""
	If '##class(%File).Exists(pFile) { Quit $System.Status.Error(5001, "Policy file not found: "_pFile) }
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$System.Status.IsError(tSC) tSC
	Set tAll = "", tNo = 0
	While 'tStream.AtEnd {
		Set tLine = tStream.ReadLine(), tNo = tNo + 1
		Set tAll = tAll_tLine_$Char(10)
		Continue:$ZStrip(tLine, "<>W")=""
		Set tObj = ""
		Try { Set tObj = {}.%FromJSON(tLine) } Catch ex { Set tObj = "" }
		If '$IsObject(tObj) { Quit }
		Set tBad = ""
		For tField = "id", "source", "title", "text" { Set:(tObj.%Get(tField)="")&&(tBad="") tBad = tField }
		If tBad '= "" { Set tSC = $System.Status.Error(5001, "Policy file line "_tNo_" is missing required field '"_tBad_"'")  Quit }
		If $Data(tSeen(tObj.id)) { Set tSC = $System.Status.Error(5001, "Policy file line "_tNo_" repeats the id '"_tObj.id_"'")  Quit }
		Set tSeen(tObj.id) = 1
		Do pPassages.%Push(tObj)
	}
	If '$IsObject($Get(tObj)) && ($ZStrip($Get(tLine), "<>W") '= "") { Quit $System.Status.Error(5001, "Policy file line "_tNo_" is not valid JSON") }
	Quit:$System.Status.IsError($Get(tSC, 1)) tSC
	If pPassages.%Size() = 0 { Quit $System.Status.Error(5001, "Policy file has no passages") }
	Set pVersion = ..Hash(tAll)
	Quit $$$OK
}

/// The first 16 hex characters of the SHA-256 of the text.
ClassMethod Hash(pText As %String) As %String
{
	Set tBin = $System.Encryption.SHAHash(256, pText), tHex = ""
	For i = 1:1:8 { Set tByte = $ZHex($Ascii($Extract(tBin, i))), tHex = tHex_$Select($Length(tByte)=1:"0", 1:"")_tByte }
	Quit $ZConvert(tHex, "L")
}

/// The version stored with the policy table: the hash of the file it was last built from.
ClassMethod StoredVersion() As %String
{
	Quit $Get(^Readback("policyIndexVersion"))
}

/// Brings the policy table in step with the file: when the stored version differs, the table is emptied first
/// (no stale passage survives) and every passage is added again. Returns the version in pVersion.
ClassMethod EnsureIndexed(pEngine As Readback.Retrieval.Engine, pFile As %String = {..#File}, Output pVersion As %String) As %Status
{
	Set tSC = ..Read(pFile, .tPassages, .pVersion)
	Quit:$System.Status.IsError(tSC) tSC
	If (..StoredVersion() = pVersion) && (pEngine.PolicyRows() = tPassages.%Size()) { Quit $$$OK }
	Set tSC = pEngine.ClearPolicy()
	Quit:$System.Status.IsError(tSC) tSC
	Set tIter = tPassages.%GetIterator()
	While tIter.%GetNext(.tKey, .tPassage) {
		Set tSC = pEngine.AddPassage(tPassage)
		Quit:$System.Status.IsError(tSC)
	}
	Quit:$System.Status.IsError(tSC) tSC
	Set ^Readback("policyIndexVersion") = pVersion
	Quit $$$OK
}

}
