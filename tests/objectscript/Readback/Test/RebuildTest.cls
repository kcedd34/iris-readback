/// P-5: a decision is rebuilt from its trace record alone and equals what was stored.
Class Readback.Test.RebuildTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

ClassMethod Clean()
{
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'RBT-%')
}

/// Stores a record the way the process does: the composer decides, the record keeps the inputs and the result.
ClassMethod Store(pId As %String, pFloor As %Integer, pValid As %Boolean, pDecision As %String, pSeverity As %Integer, pKind As %String = "", pReason As %String = "", pConfidence As %String = "high") As %Integer
{
	Set tFloor = ##class(Readback.Triage.FloorResult).%New()
	Set tFloor.Severity = pFloor
	Set tAgent = ##class(Readback.Triage.AgentOutput).%New()
	Set tAgent.Valid = pValid, tAgent.Decision = pDecision, tAgent.Severity = pSeverity, tAgent.Confidence = pConfidence
	Set tAgent.FailureKind = pKind, tAgent.FailureReason = pReason
	Set tFinal = ##class(Readback.Triage.Composer).Compose(tFloor, tAgent)
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = "RBT-"_pId, tRow.SessionId = 1
	Set tRow.FloorSeverity = pFloor, tRow.SchemaValid = pValid, tRow.AgentConfidence = pConfidence
	If pValid { Set tRow.AgentDecision = pDecision, tRow.AgentSeverity = pSeverity }
	Set tRow.FailureKind = pKind, tRow.FailureReason = pReason
	Set tRow.FinalSeverity = tFinal.FinalSeverity, tRow.Route = tFinal.Route, tRow.Divergence = tFinal.Divergence
	Set tSC = tRow.%Save()
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.StatusException).CreateFromStatus(tSC) }
	Quit tRow.%Id()
}

Method Check(pName As %String, pId As %Integer, pRoute As %String)
{
	Set tRow = ##class(Readback.Trace.Decision).%OpenId(pId)
	Set tRes = ##class(Readback.Trace.Rebuild).Explain(pId)
	Do $$$AssertTrue(tRes.ok, pName_": the record can be rebuilt")
	Do $$$AssertEquals(tRes.route, tRow.Route, pName_": route equals the stored route")
	Do $$$AssertEquals(tRes.finalSeverity, tRow.FinalSeverity, pName_": final severity equals the stored one")
	Do $$$AssertEquals(tRes.divergence, tRow.Divergence, pName_": divergence equals the stored one")
	Do $$$AssertEquals(tRow.Route, pRoute, pName_": the stored route is the expected one")
}

Method TestEveryRouteAndDegradationIsRebuiltFromTheRecord()
{
	Do ..Check("readback by floor", ..Store("a", 3, 1, "CRITICAL", 3), "readback")
	Do ..Check("readback by the agent", ..Store("b", 0, 1, "CRITICAL", 3), "readback")
	Do ..Check("agent below the floor", ..Store("c", 3, 1, "NON_CRITICAL", 0), "readback")
	Do ..Check("release", ..Store("d", 0, 1, "NON_CRITICAL", 0), "release")
	Do ..Check("recollect", ..Store("e", 0, 1, "RECOLLECT", 0), "recollect")
	Do ..Check("needs review", ..Store("f", 0, 1, "NEEDS_REVIEW", 0), "review")
	Do ..Check("low confidence", ..Store("g", 0, 1, "NON_CRITICAL", 0, "low-confidence", "confidence low", "low"), "review")
	For tKind = "schema-invalid", "empty-or-refused", "timeout", "provider-error", "no-recorded-answer", "retrieval-unavailable" {
		Do ..Check(tKind, ..Store("k-"_tKind, 0, 0, "", "", tKind, "reason of "_tKind), "review")
		Do ..Check(tKind_" with a critical floor", ..Store("kc-"_tKind, 3, 0, "", "", tKind, "reason of "_tKind), "readback")
	}
	For tState = "result ceiling", "hourly ceiling" {
		Do ..Check("budget "_tState, ..Store("b-"_tState, 0, 0, "", "", "budget-reached", "budget reached: "_tState), "review")
		Do ..Check("budget "_tState_" with a critical floor", ..Store("bc-"_tState, 3, 0, "", "", "budget-reached", "budget reached: "_tState), "readback")
	}
	For tReason = "unit not convertible", "unit conversion unavailable" {
		Do ..Check(tReason, ..Store("u-"_tReason, 0, 1, "NON_CRITICAL", 0, "unit-not-in-rule-table", tReason), "review")
	}
}

Method TestRecordWithAMissingFieldGivesAnErrorTextNotAGuess()
{
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = "RBT-missing", tRow.SessionId = 1
	Do tRow.%Save()
	Set tRes = ##class(Readback.Trace.Rebuild).Explain(tRow.%Id())
	Do $$$AssertTrue('tRes.ok, "a record without floor, final severity and route is not rebuilt")
	Do $$$AssertTrue(tRes.error["missing", "the error names what is missing")
	Do $$$AssertTrue(tRes.route = "", "no route is guessed")
	Set tNone = ##class(Readback.Trace.Rebuild).Explain(999999999)
	Do $$$AssertTrue('tNone.ok, "an unknown id gives an error")
}

}
