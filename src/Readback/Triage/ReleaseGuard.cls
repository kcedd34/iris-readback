/// The deterministic release guard. A result may be released automatically (route release, decision NON_CRITICAL) only when
///  - the floor is zero,
///  - the sample quality indices are within the limits of the policy, and
///  - the value is not in the borderline band near a critical limit.
/// Anything else goes to a person, with the reason in the trace. The agent has no say: the guard runs on the case and the floor,
/// never on the agent's answer, and nothing the agent writes can lift it.
Class Readback.Triage.ReleaseGuard
{

/// The reason a release is held, or "" when the guard lets it pass. pEffective is the lab result with its value in the reference
/// unit of the analyte; pFloor is the floor of the case.
ClassMethod Check(pEffective As Readback.Msg.LabResult, pFloor As Readback.Triage.FloorResult) As %String
{
	If pFloor.Severity > 0 { Quit "release held: the floor is "_pFloor.Severity }
	Set tLimits = ##class(Readback.Config.ReleaseGuard).Current()
	If '$IsObject(tLimits) { Quit "release held: the release guard limits are not available" }
	Set tReason = ..SampleQuality(pEffective, tLimits)
	Quit:tReason'="" tReason
	Quit ..Borderline(pEffective, tLimits.borderlineFraction)
}

/// An index above its limit of the policy. Indices without a limit are not judged; one that is not a number is held.
ClassMethod SampleQuality(pLab As Readback.Msg.LabResult, pLimits As %DynamicObject) As %String
{
	For i = 1:1:pLab.SampleIndices.Count() {
		Set tEntry = pLab.SampleIndices.GetAt(i)
		Set tCode = $Piece(tEntry, "=", 1), tValue = $Piece(tEntry, "=", 2, *)
		For j = 0:1:pLimits.sampleQualityLimits.%Size()-1 {
			Set tRow = pLimits.sampleQualityLimits.%Get(j)
			Continue:tRow.code'=tCode
			If '$IsValidNum(tValue) { Quit }
			If tValue > tRow.limit { Return "release held: sample quality outside the policy, "_tCode_" "_tValue_" is above "_tRow.limit }
		}
		If (tCode '= "") && ($Piece(tEntry, "=", 2, *) '= "") && '$IsValidNum($Piece(tEntry, "=", 2, *)) {
			Return "release held: sample quality index "_tCode_" is not a number"
		}
	}
	Quit ""
}

/// A value that reaches the given fraction of a critical high limit, or a critical low limit that reaches that fraction of the
/// value, is borderline. Uses the same range row as the floor (analyte, unit, age group, adult when the group has none).
ClassMethod Borderline(pLab As Readback.Msg.LabResult, pFraction As %Numeric) As %String
{
	Quit:pLab.ValueNumeric="" ""
	Set tAge = ##class(Readback.Triage.Floor).AgeGroup(pLab.AgeYears)
	Set tRowId = ""
	If '##class(Readback.Config.Range).RangeIdxExists(pLab.AnalyteCode, pLab.Unit, tAge, .tRowId) {
		If (tAge = "adult") || '##class(Readback.Config.Range).RangeIdxExists(pLab.AnalyteCode, pLab.Unit, "adult", .tRowId) { Quit "" }
	}
	Set tRange = ##class(Readback.Config.Range).%OpenId(tRowId)
	Quit:'$IsObject(tRange) ""
	Set tValue = pLab.ValueNumeric
	If (tRange.CriticalHigh '= "") && (tValue '< (tRange.CriticalHigh * pFraction)) {
		Quit "release held: "_pLab.ValueText_" "_pLab.Unit_" is in the borderline band, within "_$FNumber((1 - pFraction) * 100, "", 0)_" percent of the critical limit "_tRange.CriticalHigh
	}
	If (tRange.CriticalLow '= "") && (tValue '> (tRange.CriticalLow / pFraction)) {
		Quit "release held: "_pLab.ValueText_" "_pLab.Unit_" is in the borderline band near the critical limit "_tRange.CriticalLow
	}
	Quit ""
}

}
