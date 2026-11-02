/// Reads the exported history of an agent session into the ordered tool calls of the investigation. The platform hands
/// the model a failure, a denial or an unknown tool as an error message and the loop goes on, so the product reads the
/// history, not the response, to know what happened (docs/probes.md, Probe 15).
Class Readback.Agent.History
{

/// The tool calls of the session in the order the agent made them, as a list of objects with seq, id, tool, arguments
/// (the text the agent sent), result (the text a tool handed back), status and reason. Status is ok, refused (a policy
/// denied it), unknown-tool (no such tool) or failed (it ran and failed, or no result came back). Never throws.
ClassMethod Calls(pExport As %String) As %DynamicArray
{
	Set tCalls = []
	Try {
		Set tDoc = {}.%FromJSON(pExport)
		Set tMessages = tDoc.messages
		Set tIndexById = ""
		For i = 0:1:tMessages.%Size()-1 {
			Set tMessage = tMessages.%Get(i)
			Set tRole = tMessage.role
			If (tRole = "assistant") && $IsObject(tMessage.%Get("tool_calls")) {
				Set tList = tMessage.%Get("tool_calls")
				For j = 0:1:tList.%Size()-1 {
					Set tCall = tList.%Get(j)
					Set tSeq = tCalls.%Size() + 1
					Do tCalls.%Push({"seq":(tSeq),"id":(tCall.id),"tool":(tCall.name),"arguments":(tCall.arguments),"result":"","status":"failed","reason":"no result came back"})
					Set tIndexById(tCall.id) = tSeq - 1
				}
			} ElseIf tRole = "tool" {
				Set tId = tMessage."tool_call_id"
				Continue:'$Data(tIndexById(tId))
				Do ..Apply(tCalls.%Get(tIndexById(tId)), tMessage.content)
			}
		}
	} Catch ex {
		Do tCalls.%Push({"seq":1,"id":"","tool":"","arguments":"","result":"","status":"failed","reason":"the session history could not be read"})
	}
	Quit tCalls
}

/// Fills the result and the status of a call from the content of its tool message.
ClassMethod Apply(pCall As %DynamicObject, pContent As %String) [ Private ]
{
	Set tContent = pContent
	// A tool's value comes back as JSON text; a plain string value is itself JSON-encoded, so unwrap it once.
	If $Extract(tContent, 1) = """" {
		Try { Set tContent = [].%FromJSON("["_tContent_"]").%Get(0) } Catch ex {}
	}
	Set tError = ""
	If $Extract(tContent, 1) = "{" {
		Try {
			Set tObj = {}.%FromJSON(tContent)
			If tObj.%IsDefined("error") { Set tError = tObj.error }
		} Catch ex2 {}
	}
	If tError = "" {
		Set pCall.result = tContent, pCall.status = "ok", pCall.reason = ""
		Quit
	}
	Set pCall.result = ""
	Set pCall.reason = $Extract(tError, 1, 300)
	If tError [ "not found" { Set pCall.status = "unknown-tool" }
	ElseIf (tError [ "Access denied") || (tError [ "denied") { Set pCall.status = "refused" }
	Else { Set pCall.status = "failed" }
}

/// The first call that did not succeed, or "" when every call did: the case's failure for the product.
ClassMethod FirstFailure(pCalls As %DynamicArray) As %DynamicObject
{
	Set tFound = ""
	For i = 0:1:pCalls.%Size()-1 {
		Set tCall = pCalls.%Get(i)
		If tCall.status '= "ok" { Set tFound = tCall  Quit }
	}
	Quit tFound
}

}
