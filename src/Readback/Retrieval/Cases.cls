/// The pool of confirmed cases: a case is searchable only after a person confirmed it, by a matching
/// read-back (ConfirmedBy) or a completed review (ReviewedBy).
Class Readback.Retrieval.Cases
{

/// The words for the final severity in a case document.
ClassMethod DecisionWord(pSeverity As %Integer) As %String
{
	Quit $Select(pSeverity>=3:"critical", pSeverity>0:"needs attention", 1:"not critical")
}

/// The document text of a trace record: the identifier-free description of its result, then the decision and route.
/// Returns "" when the stored lab result of the case is gone.
ClassMethod Document(pTrace As Readback.Trace.Decision) As %String
{
	Set tControl = pTrace.MessageControlId
	&sql(SELECT TOP 1 ID INTO :tLabId FROM Readback_Msg.LabResult WHERE MessageControlId = :tControl ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Set tLab = ##class(Readback.Msg.LabResult).%OpenId(tLabId)
	Quit:'$IsObject(tLab) ""
	// The case is described in the reference unit when it was converted, as the floor and the agent saw it.
	If (pTrace.ConversionOutcome = "converted") || (pTrace.ConversionOutcome = "not-needed") {
		If pTrace.ConvertedValue '= "" { Set tLab.ValueText = pTrace.ConvertedValue, tLab.Unit = pTrace.ConvertedUnit }
	}
	Quit ##class(Readback.Retrieval.Describe).Text(tLab)_" Decision: "_..DecisionWord(pTrace.FinalSeverity)_". Route: "_pTrace.Route_"."
}

/// Adds the confirmed cases not yet indexed and removes the ones whose trace record no longer exists.
ClassMethod Sync(pEngine As Readback.Retrieval.Engine) As %Status
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Readback_Trace.Decision WHERE ((ConfirmedBy IS NOT NULL AND ConfirmedBy <> '') OR (ReviewedBy IS NOT NULL AND ReviewedBy <> '')) AND ID NOT IN (SELECT TraceId FROM Readback_Retrieval.IndexedCase) ORDER BY ID")
	If tRS.%SQLCODE < 0 { Quit $System.Status.Error(5001, "Case sync failed: "_tRS.%Message) }
	Set tN = 0
	While tRS.%Next() { Set tN = tN + 1, tIds(tN) = tRS.%Get("ID") }
	For i = 1:1:tN {
		Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tIds(i))
		Continue:'$IsObject(tTrace)
		Set tDoc = ..Document(tTrace)
		Continue:tDoc=""
		Set tSC = pEngine.AddCase(tIds(i), tDoc)
		Quit:$System.Status.IsError(tSC)
		Set tMark = ##class(Readback.Retrieval.IndexedCase).%New()
		Set tMark.TraceId = tIds(i)
		Set tSC = tMark.%Save()
		Quit:$System.Status.IsError(tSC)
	}
	Quit:$System.Status.IsError($Get(tSC, 1)) tSC
	// Cases whose trace record was deleted leave the pool.
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, TraceId FROM Readback_Retrieval.IndexedCase WHERE TraceId NOT IN (SELECT ID FROM Readback_Trace.Decision)")
	If tRS.%SQLCODE < 0 { Quit $System.Status.Error(5001, "Case sync failed: "_tRS.%Message) }
	Set tM = 0
	While tRS.%Next() { Set tM = tM + 1, tGone(tM) = tRS.%Get("ID")_"^"_tRS.%Get("TraceId") }
	For i = 1:1:tM {
		Set tSC = pEngine.RemoveCase($Piece(tGone(i), "^", 2))
		Quit:$System.Status.IsError(tSC)
		Do ##class(Readback.Retrieval.IndexedCase).%DeleteId($Piece(tGone(i), "^", 1))
	}
	Quit $Get(tSC, $$$OK)
}

}
