/// One short English line for a tool call, for the visual trace and the flow. Built from the call, never the raw result.
Class Readback.Tools.Summary
{

ClassMethod Of(pTool As %String, pStatus As %String, pResult As %String, pReason As %String = "") As %String
{
	If pStatus = "refused" { Quit "refused by the policy" }
	If pStatus = "unknown-tool" { Quit "no such tool" }
	If pStatus = "failed" { Quit "the tool failed" }
	Set tObj = ""
	If $Extract(pResult, 1) = "{" { Try { Set tObj = {}.%FromJSON(pResult) } Catch ex { Set tObj = "" } }
	If '$IsObject(tObj) { Quit "answered" }
	If pTool = "get_patient_history" {
		Set tN = +tObj.found
		Quit $Case(tN, 0:"no earlier results", 1:"1 earlier result", :tN_" earlier results")
	}
	If pTool = "get_delta_assessment" { Quit tObj.floorVerdict }
	If pTool = "search_policy" {
		If 'tObj.available { Quit "policy search unavailable" }
		Quit tObj.passages.%Size()_" policy passages"
	}
	If pTool = "get_sample_quality" {
		Set tN = tObj.indices.%Size()
		Quit $Case(tN, 0:"no quality indices", 1:"1 quality index", :tN_" quality indices")
	}
	Quit "answered"
}

/// The tool calls of a decision in order, as short entries for the flow: seq, tool, status and a one-line summary. Never the
/// arguments or the raw result.
ClassMethod ForDecision(pDecisionId As %String) As %DynamicArray
{
	Set tList = []
	Quit:pDecisionId="" tList
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Seq, Tool, Status, Reason, ResultJson FROM Readback_Trace.ToolCall WHERE Decision = ? ORDER BY Seq", pDecisionId)
	While tRS.%Next() {
		Do tList.%Push({"seq":(tRS.%Get("Seq")),"tool":(tRS.%Get("Tool")),"status":(tRS.%Get("Status")),"summary":(..Of(tRS.%Get("Tool"), tRS.%Get("Status"), tRS.%Get("ResultJson"), tRS.%Get("Reason")))})
	}
	Quit tList
}

}
