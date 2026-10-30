/// The escalation list and the windows, read from data/config/escalation.json. The platform's alert management does the
/// escalating; this class only says who is alerted at a level and how long a level lasts.
Class Readback.Notify.Escalation
{

Parameter GLOBAL = "^Readback(""escalation"")";

/// Reads and checks the file, and keeps it for the next alert. Returns an error status with the reason when the file is
/// missing or invalid; the configuration already loaded is then left as it was.
ClassMethod Load(pFile As %String = "") As %Status
{
	Set:pFile="" pFile=##class(Readback.Config.Paths).Data()_"/config/escalation.json"
	Quit:'##class(%File).Exists(pFile) $System.Status.Error(5001, "escalation file not found: "_pFile)
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$System.Status.IsError(tSC) tSC
	Set tWhy = ""
	Try {
		Set tObj = {}.%FromJSON(tStream)
		Set tWhy = ..Check(tObj)
	} Catch ex {
		Set tWhy = "the file is not valid JSON or does not have the expected shape"
	}
	Quit:tWhy'="" $System.Status.Error(5001, "escalation file is invalid: "_tWhy)
	Set tLevels = ""
	For i = 0:1:tObj.levels.%Size() - 1 { Set tLevels = tLevels_$ListBuild(tObj.levels.%Get(i).recipient) }
	Set @..#GLOBAL = $ListBuild(tObj.firstWindowSeconds, tObj.windowSeconds, tLevels)
	Quit $$$OK
}

/// "" when the object is valid, else the reason: at least one level, every window a positive integer, recipients non-empty strings.
ClassMethod Check(pObj As %DynamicObject) As %String
{
	If '$IsObject(pObj) || (pObj.%IsA("%Library.DynamicArray")) { Quit "the file must hold one object" }
	If '$IsObject(pObj.levels) { Quit "levels must be a list with at least one level" }
	If pObj.levels.%Size() < 1 { Quit "levels must have at least one level" }
	If '..PositiveInteger(pObj.firstWindowSeconds) { Quit "firstWindowSeconds must be a positive integer" }
	If '..PositiveInteger(pObj.windowSeconds) { Quit "windowSeconds must be a positive integer" }
	Set tWhy = ""
	For i = 0:1:pObj.levels.%Size() - 1 {
		Set tLevel = pObj.levels.%Get(i)
		If '$IsObject(tLevel) { Set tWhy = "every level needs a non-empty recipient" }
		ElseIf $ZStrip(tLevel.recipient, "<>W") = "" { Set tWhy = "every level needs a non-empty recipient" }
	}
	Quit tWhy
}

ClassMethod PositiveInteger(pValue As %String) As %Boolean
{
	Quit (pValue '= "") && (pValue = (+pValue \ 1)) && (pValue >= 1)
}

ClassMethod IsLoaded() As %Boolean
{
	Quit $Data(@..#GLOBAL) > 0
}

/// Forgets the loaded configuration (tests).
ClassMethod Clear()
{
	Kill @..#GLOBAL
}

ClassMethod Levels() As %Integer
{
	Quit:'..IsLoaded() 0
	Quit $ListLength($List(@..#GLOBAL, 3))
}

/// Seconds the first person has before the alert escalates.
ClassMethod FirstWindow() As %Integer
{
	Quit:'..IsLoaded() 0
	Quit $List(@..#GLOBAL, 1)
}

/// Seconds every later level has.
ClassMethod Window() As %Integer
{
	Quit:'..IsLoaded() 0
	Quit $List(@..#GLOBAL, 2)
}

/// The person alerted at a level; the last person for a level beyond the list.
ClassMethod RecipientFor(pLevel As %Integer) As %String
{
	Quit:'..IsLoaded() ""
	Set tList = $List(@..#GLOBAL, 3)
	Set tIndex = $Select((pLevel '= (+pLevel \ 1)) || (pLevel < 0):1, 1:pLevel + 1)
	Quit $List(tList, $Select(tIndex > $ListLength(tList):$ListLength(tList), 1:tIndex))
}

/// The level after pLevel, never past the last one.
ClassMethod NextLevel(pLevel As %Integer) As %Integer
{
	Set tLast = ..Levels() - 1
	Quit:(tLast<0) pLevel
	Quit $Select(pLevel < tLast:pLevel + 1, 1:tLast)
}

/// True at or past the last level: nobody is left to escalate to.
ClassMethod IsExhausted(pLevel As %Integer) As %Boolean
{
	Quit:'..IsLoaded() 0
	Quit pLevel >= (..Levels() - 1)
}

}
