/// Indicators over stored trace records: hand-computed values, empty windows, windows by time.
Class Readback.Test.IndicatorsTest Extends %UnitTest.TestCase
{

Parameter From = "2001-01-01 00:00:00";

Parameter To = "2001-01-01 23:59:59";

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
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'IND-%')
}

ClassMethod Row(pN As %Integer, pStamp As %String, pRoute As %String, pDivergence As %String, pValid As %Boolean, pKind As %String, pCalled As %Boolean, pLatency As %Integer, pCost As %String)
{
	Set tRow = ##class(Readback.Trace.Decision).%New()
	Set tRow.MessageControlId = "IND-"_pN, tRow.SessionId = 1, tRow.CreatedAt = pStamp
	Set tRow.Route = pRoute, tRow.Divergence = pDivergence, tRow.SchemaValid = pValid, tRow.FailureKind = pKind
	Set tRow.AgentCalled = pCalled, tRow.LatencyMs = pLatency
	If pCost '= "" { Set tRow.CostUsd = pCost, tRow.CostKnown = 1 }
	Set tSC = tRow.%Save()
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.StatusException).CreateFromStatus(tSC) }
}

/// 20 records in the window 2001-01-01: 16 call the agent with latencies 100..1600, 4 do not (latency 9999 must not count).
/// Routes: 7 review. Divergence on 2. Invalid: 1 schema-invalid, 1 empty-or-refused, 1 timeout (not counted). Cost known on 10, 0.002 each.
Method TestFiguresEqualTheHandValues()
{
	Do ..Seed()
	Set tRes = ##class(Readback.Trace.Indicators).Compute(..#From, ..#To)
	Do $$$AssertEquals(tRes.recordCount, 20, "twenty records in the window")
	Do $$$AssertEquals(tRes.costPerThousandResults, 2, "10 known costs of 0.002: the mean is 0.002, times 1000 is 2")
	Do $$$AssertEquals(tRes.unknownCostRecords, 10, "the ten records without a price are counted apart")
	Do $$$AssertEquals(tRes.latencyP50Ms, 800, "nearest rank 50 of 16 values is the 8th: 800")
	Do $$$AssertEquals(tRes.latencyP95Ms, 1600, "nearest rank 95 of 16 values is the 16th: 1600")
	Do $$$AssertEquals(tRes.reviewRate, 0.35, "7 of 20 are review")
	Do $$$AssertEquals(tRes.divergenceRate, 0.1, "2 of 20 diverge")
	Do $$$AssertEquals(tRes.invalidRate, 0.1, "schema-invalid and empty-or-refused are 2 of 20; a timeout is not an invalid answer")
}

ClassMethod Seed()
{
	Do ..Clean()
	Set tDay = "2001-01-01 "
	For i = 1:1:20 {
		Set tCalled = (i <= 16)
		Set tLatency = $Select(tCalled:i*100, 1:9999)
		Set tRoute = $Select(i<=7:"review", i<=12:"readback", 1:"release")
		Set tDiv = $Select(i<=2:"agent below floor", 1:"")
		Set tValid = 1, tKind = ""
		If i = 8 { Set tValid = 0, tKind = "schema-invalid" }
		If i = 9 { Set tValid = 0, tKind = "empty-or-refused" }
		If i = 10 { Set tValid = 0, tKind = "timeout" }
		Do ..Row(i, tDay_$Translate($Justify(i, 2), " ", "0")_":00:00", tRoute, tDiv, tValid, tKind, tCalled, tLatency, $Select(i<=10:0.002, 1:""))
	}
}

Method TestWindowUsesOnlyTheRecordsInsideIt()
{
	Do ..Seed()
	Set tRes = ##class(Readback.Trace.Indicators).Compute("2001-01-01 00:00:00", "2001-01-01 05:59:59")
	Do $$$AssertEquals(tRes.recordCount, 5, "hours 01 to 05 hold five records")
	Set tRes = ##class(Readback.Trace.Indicators).Compute("2001-01-01 20:00:00", "2001-01-01 23:59:59")
	Do $$$AssertEquals(tRes.recordCount, 1, "hour 20 only")
}

Method TestEmptyWindowGivesNullFigures()
{
	Set tRes = ##class(Readback.Trace.Indicators).Compute("1999-01-01 00:00:00", "1999-01-02 00:00:00")
	Do $$$AssertEquals(tRes.recordCount, 0, "no record")
	For tName = "costPerThousandResults", "unknownCostRecords", "latencyP50Ms", "latencyP95Ms", "reviewRate", "divergenceRate", "invalidRate" {
		Do $$$AssertEquals(tRes.%GetTypeOf(tName), "null", tName_" is null")
	}
}

Method TestUnknownCostIsNeverZero()
{
	Do ..Clean()
	Do ..Row(1, "2001-02-01 01:00:00", "release", "", 1, "", 1, 100, "")
	Set tRes = ##class(Readback.Trace.Indicators).Compute("2001-02-01 00:00:00", "2001-02-01 23:59:59")
	Do $$$AssertEquals(tRes.%GetTypeOf("costPerThousandResults"), "null", "with no known cost the figure is null, not 0")
	Do $$$AssertEquals(tRes.unknownCostRecords, 1, "the record is counted as unknown")
}

Method TestNearestRankAndTimestampCheck()
{
	Do $$$AssertEquals(##class(Readback.Trace.Indicators).Rank(50, 5), 3, "50 of 5 is rank 3")
	Do $$$AssertEquals(##class(Readback.Trace.Indicators).Rank(95, 20), 19, "95 of 20 is rank 19")
	Do $$$AssertEquals(##class(Readback.Trace.Indicators).Rank(95, 1), 1, "one value is its own percentile")
	Do $$$AssertTrue(##class(Readback.Trace.Indicators).Valid("2026-03-01 08:30:00"), "a timestamp is accepted")
	Do $$$AssertTrue(##class(Readback.Trace.Indicators).Valid(""), "empty is accepted")
	Do $$$AssertTrue('##class(Readback.Trace.Indicators).Valid("yesterday"), "text is refused")
	Do $$$AssertTrue('##class(Readback.Trace.Indicators).Valid("2026-13-45 99:00:00"), "an impossible date is refused")
}

}
