/// The limits of the release guard, read from data/config/release-guard.json. A file that cannot be read or is malformed
/// returns "": the guard then holds every release (it fails closed, never open).
Class Readback.Config.ReleaseGuard
{

/// The limits as a dynamic object {borderlineFraction, sampleQualityLimits:[{code, limit}]}, or "" when unusable.
ClassMethod Current() As %DynamicObject
{
	Set tFile = ##class(Readback.Config.Paths).Data()_"/config/release-guard.json"
	Set tDoc = ""
	Try {
		Set tStream = ##class(%Stream.FileCharacter).%New()
		Set tSC = tStream.LinkToFile(tFile)
		Quit:$System.Status.IsError(tSC)
		Set tDoc = {}.%FromJSON(tStream.Read(100000))
	} Catch ex {
		Set tDoc = ""
	}
	Quit:'$IsObject(tDoc) ""
	Set tFraction = tDoc.borderlineFraction
	If (tDoc.%GetTypeOf("borderlineFraction") '= "number") || (tFraction '> 0) || (tFraction '< 1) { Quit "" }
	If '$IsObject(tDoc.sampleQualityLimits) { Quit "" }
	For i = 0:1:tDoc.sampleQualityLimits.%Size()-1 {
		Set tRow = tDoc.sampleQualityLimits.%Get(i)
		If (tRow.code = "") || (tRow.%GetTypeOf("limit") '= "number") { Quit }
	}
	Quit tDoc
}

}
