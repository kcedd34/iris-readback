/// Figures derived from the stored trace records, as data only. A figure with nothing to compute from is null.
Class Readback.Trace.Indicators
{

/// pFrom and pTo are timestamps (YYYY-MM-DD hh:mm:ss) or empty; the window is inclusive. Check them with Valid first.
ClassMethod Compute(pFrom As %String = "", pTo As %String = "") As %DynamicObject
{
	Set tRes = {}
	Do tRes.%Set("from", $Select(pFrom="":"", 1:pFrom), $Select(pFrom="":"null", 1:"string"))
	Do tRes.%Set("to", $Select(pTo="":"", 1:pTo), $Select(pTo="":"null", 1:"string"))
	Set tLow = $Select(pFrom="":"0000-01-01 00:00:00", 1:pFrom), tHigh = $Select(pTo="":"9999-12-31 23:59:59", 1:pTo)
	&sql(SELECT COUNT(*), SUM(CASE WHEN Route = 'review' THEN 1 ELSE 0 END), SUM(CASE WHEN Divergence IS NOT NULL AND Divergence <> '' THEN 1 ELSE 0 END),
	            SUM(CASE WHEN SchemaValid = 0 AND FailureKind IN ('schema-invalid','empty-or-refused') THEN 1 ELSE 0 END),
	            SUM(CASE WHEN CostKnown = 1 THEN 1 ELSE 0 END), SUM(CASE WHEN CostKnown = 1 THEN CostUsd ELSE 0 END)
	     INTO :tCount, :tReview, :tDiverge, :tInvalid, :tKnown, :tCostSum
	     FROM Readback_Trace.Decision WHERE CreatedAt >= :tLow AND CreatedAt <= :tHigh)
	If SQLCODE < 0 { Throw ##class(%Exception.General).%New("indicators query failed", SQLCODE) }
	Set tCount = +$Get(tCount), tKnown = +$Get(tKnown)
	// The investigation: how often the floor policy refused a lowering answer, how often a tool call did not succeed, and how many rounds and tool calls a decision takes.
	&sql(SELECT SUM(CASE WHEN PolicyRefusal IS NOT NULL AND PolicyRefusal <> '' THEN 1 ELSE 0 END), SUM(CASE WHEN ToolFailureCount > 0 THEN 1 ELSE 0 END),
	            AVG(CAST(COALESCE(Rounds, 1) AS DOUBLE)), AVG(CAST(COALESCE(ToolCallCount, 0) AS DOUBLE))
	     INTO :tRefused, :tToolFail, :tRounds, :tCalls
	     FROM Readback_Trace.Decision WHERE CreatedAt >= :tLow AND CreatedAt <= :tHigh)
	If SQLCODE < 0 { Throw ##class(%Exception.General).%New("indicators query failed", SQLCODE) }
	Set tRes.recordCount = tCount
	If tCount = 0 {
		For tName = "costPerThousandResults", "unknownCostRecords", "latencyP50Ms", "latencyP95Ms", "reviewRate", "divergenceRate", "invalidRate", "policyRefusalRate", "toolFailureRate", "meanRounds", "meanToolCalls" { Do tRes.%Set(tName, "", "null") }
		Quit tRes
	}
	If tKnown > 0 { Set tRes.costPerThousandResults = +$FNumber(tCostSum / tKnown * 1000, "", 6) } Else { Do tRes.%Set("costPerThousandResults", "", "null") }
	Set tRes.unknownCostRecords = tCount - tKnown
	Set tRes.reviewRate = +$FNumber(+$Get(tReview) / tCount, "", 6)
	Set tRes.divergenceRate = +$FNumber(+$Get(tDiverge) / tCount, "", 6)
	Set tRes.invalidRate = +$FNumber(+$Get(tInvalid) / tCount, "", 6)
	Set tRes.policyRefusalRate = +$FNumber(+$Get(tRefused) / tCount, "", 6)
	Set tRes.toolFailureRate = +$FNumber(+$Get(tToolFail) / tCount, "", 6)
	Set tRes.meanRounds = +$FNumber(+$Get(tRounds), "", 4)
	Set tRes.meanToolCalls = +$FNumber(+$Get(tCalls), "", 4)
	Do ..Latencies(tLow, tHigh, tRes)
	Quit tRes
}

/// Nearest rank over the records that called the agent: the value at position ceiling(p * n / 100) of the sorted list.
ClassMethod Latencies(pLow As %String, pHigh As %String, pRes As %DynamicObject) [ Private ]
{
	Kill ^||lat
	Set tN = 0
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT LatencyMs FROM Readback_Trace.Decision WHERE AgentCalled = 1 AND LatencyMs IS NOT NULL AND CreatedAt >= ? AND CreatedAt <= ? ORDER BY LatencyMs", pLow, pHigh)
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("latency query failed", tRS.%SQLCODE) }
	While tRS.%Next() { Set tN = tN + 1, ^||lat(tN) = tRS.%GetData(1) }
	If tN = 0 {
		Do pRes.%Set("latencyP50Ms", "", "null"), pRes.%Set("latencyP95Ms", "", "null")
	} Else {
		Set pRes.latencyP50Ms = +^||lat(..Rank(50, tN)), pRes.latencyP95Ms = +^||lat(..Rank(95, tN))
	}
	Kill ^||lat
}

ClassMethod Rank(pPercent As %Integer, pN As %Integer) As %Integer
{
	Set tRank = pPercent * pN \ 100
	If (pPercent * pN) # 100 { Set tRank = tRank + 1 }
	Quit $Select(tRank<1:1, tRank>pN:pN, 1:tRank)
}

/// True when pText is empty or a timestamp of the form YYYY-MM-DD hh:mm:ss.
ClassMethod Valid(pText As %String) As %Boolean
{
	Quit:pText="" 1
	Quit:'$Match(pText, "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}") 0
	Set tOk = 1
	Try { Set tH = $ZDateTimeH(pText, 3, 1) } Catch ex { Set tOk = 0 }
	Quit tOk
}

}
