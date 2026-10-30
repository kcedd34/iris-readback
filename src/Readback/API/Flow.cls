/// Read-only views for the flow panel and the read-back task screen, plus the limited submit of a shipped demo
/// scenario. Everything comes from the product's own tables; the platform's internals are not read, except the
/// managed alert list that Readback.Notify.Alerts already reads. Errors go through Readback.API.Status.Fail, so
/// every error body is {"error":"..."} and never holds a key, a stack or a header.
Class Readback.API.Flow
{

/// Decisions returned by one /flow call. The caller asks again with the new cursor when it got this many.
Parameter MaxDecided = 200;

/// Waiting cases listed (newest first); waitingTotal says how many exist.
Parameter MaxWaiting = 200;

/// Recently confirmed cases listed, so the panel can say who confirmed a case that left the waiting list.
Parameter MaxConfirmed = 20;

/// Results still being decided are listed only for this long after they arrived (seconds).
Parameter InFlightSeconds = 300;

/// A new submission is refused while this many results are in flight.
Parameter MaxInFlight = 10;

/// A submission is refused when the account submitted less than this many seconds ago.
Parameter SubmitGapSeconds = 1;

/// The scenario list and the sample messages, under the product's samples folder.
ClassMethod ScenariosFile() As %String
{
	Quit ##class(Readback.Config.Paths).Samples()_"/demo-scenarios.json"
}

ClassMethod SampleDir() As %String
{
	Quit ##class(Readback.Config.Paths).Samples()
}

/// The intake folder, and the work folder where files are written first and renamed into the inbox, so the file service
/// never reads half a file.
ClassMethod Inbox() As %String
{
	Quit ##class(Readback.Config.Paths).Inbox()
}

ClassMethod Staging() As %String
{
	Quit ##class(Readback.Config.Paths).Work()
}

// ----------------------------------------------------------------------------------------------------------
// REST handlers (called from Readback.API.Status)
// ----------------------------------------------------------------------------------------------------------

ClassMethod GetFlow() As %Status
{
	Set tAfter = ""
	If $Data(%request.Data("after", 1)) {
		Set tAfter = %request.Data("after", 1)
		If (tAfter '? 1.N) { Quit ##class(Readback.API.Status).Fail(400, "after must be a non-negative whole number") }
	}
	Write ..Snapshot(tAfter).%ToJSON()
	Quit $$$OK
}

ClassMethod GetSamples() As %Status
{
	Set tList = ..LoadScenarios()
	If '$IsObject(tList) { Quit ##class(Readback.API.Status).Fail(500, "the demo scenarios are not available") }
	Set tOut = []
	Set tIter = tList.%GetIterator()
	While tIter.%GetNext(.tKey, .tScenario) {
		Do tOut.%Push({"id":(tScenario.id), "label":(tScenario.label), "analyte":(tScenario.analyte), "expected":(tScenario.expected), "messageCount":(tScenario.files.%Size())})
	}
	Write tOut.%ToJSON()
	Quit $$$OK
}

ClassMethod PostSubmit() As %Status
{
	Set tBody = ""
	Try {
		Set tText = $Select($IsObject(%request.Content):%request.Content.Read(1000), 1:"")
		Set tBody = {}.%FromJSON(tText)
	} Catch ex {
		Set tBody = ""
	}
	If '$IsObject(tBody) || (tBody.%GetTypeOf("scenarioId") '= "string") || (tBody.%Size() '= 1) {
		Quit ##class(Readback.API.Status).Fail(400, "send {""scenarioId"": ""<id>""} and nothing else")
	}
	Set tScenario = ..FindScenario(tBody.scenarioId)
	If '$IsObject(tScenario) { Quit ##class(Readback.API.Status).Fail(400, "unknown scenario") }
	Set tWho = $USERNAME
	If ..InFlightCount() >= ..#MaxInFlight { Quit ##class(Readback.API.Status).Fail(429, "too many results are being decided; try again in a moment") }
	Set tNow = $ZHorolog, tLast = +$Get(^Readback("flowSubmit", tWho))
	If (tNow - tLast) < ..#SubmitGapSeconds { Quit ##class(Readback.API.Status).Fail(429, "too frequent; wait a second and try again") }
	Set ^Readback("flowSubmit", tWho) = tNow
	Set tSC = ..Drop(tScenario, .tControlIds)
	If $System.Status.IsError(tSC) { Quit ##class(Readback.API.Status).Fail(500, $System.Status.GetErrorText(tSC)) }
	Write {"accepted":true, "controlIds":(tControlIds)}.%ToJSON()
	Quit $$$OK
}

ClassMethod GetTaskView(pDecisionId As %String) As %Status
{
	Set tView = ..TaskView(pDecisionId, $USERNAME)
	If tView = "" { Quit ##class(Readback.API.Status).Fail(404, "no read-back task for that case") }
	Write tView.%ToJSON()
	Quit $$$OK
}

// ----------------------------------------------------------------------------------------------------------
// The snapshot
// ----------------------------------------------------------------------------------------------------------

/// pAfter empty: start from now (cursor is the newest decision, nothing in decided). A number: decisions with an id
/// above it, oldest first, at most MaxDecided.
ClassMethod Snapshot(pAfter As %String = "") As %DynamicObject
{
	Set tRes = {}
	Set tRes.mode = ##class(Readback.Config.Mode).Current()
	Set tMax = ..MaxDecisionId()
	Set tDecided = []
	Set tCursor = tMax
	If pAfter '= "" {
		Set tCursor = +pAfter
		Set tStmt = ##class(%SQL.Statement).%New()
		Set tSC = tStmt.%Prepare("SELECT TOP "_..#MaxDecided_" ID FROM Readback_Trace.Decision WHERE ID > ? ORDER BY ID")
		If $System.Status.IsError(tSC) { Throw ##class(%Exception.General).%New("decision list failed", 5001) }
		Set tRS = tStmt.%Execute(+pAfter)
		If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("decision list failed", tRS.%SQLCODE) }
		While tRS.%Next() {
			Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tRS.%Get("ID"))
			Continue:'$IsObject(tTrace)
			Do tDecided.%Push(..DecidedEntry(tTrace))
			Set tCursor = tRS.%Get("ID")
		}
	}
	Set tRes.cursor = tCursor
	Set tRes.decided = tDecided
	Set tRes.inFlight = ..InFlight()
	Set tWaiting = ..Waiting(.tTotal)
	Set tRes.waiting = tWaiting
	Set tRes.waitingTotal = tTotal
	Set tRes.confirmed = ..RecentlyConfirmed()
	Quit tRes
}

ClassMethod MaxDecisionId() As %Integer
{
	&sql(SELECT MAX(ID) INTO :tMax FROM Readback_Trace.Decision)
	If SQLCODE < 0 { Throw ##class(%Exception.General).%New("decision max failed", SQLCODE) }
	Quit +$Get(tMax)
}

ClassMethod DecidedEntry(pTrace As Readback.Trace.Decision) As %DynamicObject
{
	Set tWhy = ##class(Readback.Trace.Rebuild).ExplainRecord(pTrace)
	Set tEntry = {}
	Set tEntry.decisionId = +pTrace.%Id()
	Set tEntry.controlId = pTrace.MessageControlId
	Set tEntry.analyte = ..AnalyteName(pTrace.MessageControlId)
	Set tEntry.route = pTrace.Route
	Set tEntry.finalSeverity = pTrace.FinalSeverity
	Set tEntry.reason = ##class(Readback.Config.Mode).Redact($Select(tWhy.ok:tWhy.reason, 1:""))
	Set tEntry.floorNote = ##class(Readback.Config.Mode).Redact(pTrace.FloorNote)
	Set tEntry.failureKind = pTrace.FailureKind
	Do tEntry.%Set("agentCalled", ''pTrace.AgentCalled, "boolean")
	Do:pTrace.RecordedLatencyMs'="" tEntry.%Set("recordedLatencyMs", +pTrace.RecordedLatencyMs, "number")
	Set tEntry.mode = pTrace.Mode
	Set tEntry.decidedAt = pTrace.CreatedAt
	Quit tEntry
}

/// The analyte name of the latest stored result of a case, or its code, or empty.
ClassMethod AnalyteName(pControlId As %String) As %String
{
	&sql(SELECT TOP 1 AnalyteCode INTO :tCode FROM Readback_Msg.LabResult WHERE MessageControlId = :pControlId ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	If ##class(Readback.Config.Analyte).CodeIdxExists(tCode, .tId) { Quit ##class(Readback.Config.Analyte).%OpenId(tId).Name }
	Quit tCode
}

/// Results stored and not yet decided, recent only. A case id received twice counts once per result without a decision.
ClassMethod InFlight() As %DynamicArray
{
	Set tList = []
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare(..InFlightSql("l.MessageControlId, l.AnalyteCode, l.ReceivedAt")_" ORDER BY l.ID")
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.General).%New("in flight failed", 5001) }
	Set tRS = tStmt.%Execute(..Cutoff())
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("in flight failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tCode = tRS.%Get("AnalyteCode"), tName = tCode
		If ##class(Readback.Config.Analyte).CodeIdxExists(tCode, .tId) { Set tName = ##class(Readback.Config.Analyte).%OpenId(tId).Name }
		Do tList.%Push({"controlId":(tRS.%Get("MessageControlId")), "analyte":(tName), "enteredAt":(tRS.%Get("ReceivedAt"))})
	}
	Quit tList
}

ClassMethod InFlightCount() As %Integer
{
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare(..InFlightSql("COUNT(*) AS N"))
	Quit:$System.Status.IsError(tSC) 0
	Set tRS = tStmt.%Execute(..Cutoff())
	Quit:tRS.%SQLCODE<0 0
	Do tRS.%Next()
	Quit +tRS.%Get("N")
}

ClassMethod InFlightSql(pColumns As %String) As %String
{
	Quit "SELECT "_pColumns_" FROM Readback_Msg.LabResult l WHERE l.ReceivedAt >= ? AND (SELECT COUNT(*) FROM Readback_Msg.LabResult l2 WHERE l2.MessageControlId = l.MessageControlId) > (SELECT COUNT(*) FROM Readback_Trace.Decision d WHERE d.MessageControlId = l.MessageControlId)"
}

/// The UTC timestamp InFlightSeconds ago, in the form of ReceivedAt.
ClassMethod Cutoff() As %String
{
	Set tNow = $ZTimeStamp, tDay = $Piece(tNow, ",", 1), tSec = $Piece(tNow, ",", 2) - ..#InFlightSeconds
	While tSec < 0 { Set tSec = tSec + 86400, tDay = tDay - 1 }
	Quit $ZDateTime(tDay_","_tSec, 3, 1, 3)
}

/// Decisions routed to read-back and not confirmed, newest first, with the person the task is assigned to.
ClassMethod Waiting(Output pTotal As %Integer) As %DynamicArray
{
	Set tList = []
	&sql(SELECT COUNT(*) INTO :pTotal FROM Readback_Trace.Decision WHERE Route = 'readback' AND ConfirmedAt IS NULL)
	If SQLCODE < 0 { Throw ##class(%Exception.General).%New("waiting count failed", SQLCODE) }
	Set tAlerts = ##class(Readback.Notify.Alerts).Open()
	Set tIter = tAlerts.%GetIterator()
	While tIter.%GetNext(.tKey, .tAlert) { Set tByCase(tAlert.controlId) = tAlert }
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_..#MaxWaiting_" ID FROM Readback_Trace.Decision WHERE Route = 'readback' AND ConfirmedAt IS NULL ORDER BY ID DESC")
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.General).%New("waiting list failed", 5001) }
	Set tRS = tStmt.%Execute()
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("waiting list failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tTrace = ##class(Readback.Trace.Decision).%OpenId(tRS.%Get("ID"))
		Continue:'$IsObject(tTrace)
		Set tEntry = {}
		Set tEntry.decisionId = +tTrace.%Id()
		Set tEntry.controlId = tTrace.MessageControlId
		Set tEntry.analyte = ..AnalyteName(tTrace.MessageControlId)
		Set tEntry.since = tTrace.CreatedAt
		Set tEntry.taskId = tTrace.TaskId
		Set tEntry.assignedTo = ..AssignedTo(tTrace.TaskId)
		Set tEntry.mode = tTrace.Mode
		If $Data(tByCase(tTrace.MessageControlId)) {
			Set tEntry.alertLevel = tByCase(tTrace.MessageControlId).level
			Set tEntry.alertState = tByCase(tTrace.MessageControlId).state
		}
		Do tList.%Push(tEntry)
	}
	Quit tList
}

/// The person a read-back task is assigned to, or empty (unassigned, or no numeric task id).
ClassMethod AssignedTo(pTaskId As %String) As %String
{
	Quit:(pTaskId '? 1.N) ""
	&sql(SELECT TaskStatus_AssignedTo INTO :tUser FROM Readback_Workflow.ReadbackTask WHERE ID = :pTaskId)
	Quit:SQLCODE'=0 ""
	Quit $Get(tUser)
}

ClassMethod RecentlyConfirmed() As %DynamicArray
{
	Set tList = []
	Set tStmt = ##class(%SQL.Statement).%New()
	Set tSC = tStmt.%Prepare("SELECT TOP "_..#MaxConfirmed_" ID, MessageControlId, ConfirmedBy, ConfirmedAt, ReadbackMatch FROM Readback_Trace.Decision WHERE ConfirmedAt IS NOT NULL ORDER BY ConfirmedAt DESC")
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.General).%New("confirmed list failed", 5001) }
	Set tRS = tStmt.%Execute()
	If tRS.%SQLCODE < 0 { Throw ##class(%Exception.General).%New("confirmed list failed", tRS.%SQLCODE) }
	While tRS.%Next() {
		Set tItem = {"decisionId":(+tRS.%Get("ID")), "controlId":(tRS.%Get("MessageControlId")), "confirmedBy":(tRS.%Get("ConfirmedBy")), "confirmedAt":(tRS.%Get("ConfirmedAt"))}
		Do tItem.%Set("readbackMatch", ''tRS.%Get("ReadbackMatch"), "boolean")
		Do tList.%Push(tItem)
	}
	Quit tList
}

// ----------------------------------------------------------------------------------------------------------
// Scenarios and the submit
// ----------------------------------------------------------------------------------------------------------

/// The scenario list of data/samples/demo-scenarios.json as a %DynamicArray, or "" when it cannot be read.
ClassMethod LoadScenarios() As %DynamicArray
{
	Set tFile = ..ScenariosFile()
	Quit:'##class(%File).Exists(tFile) ""
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tFile)
	Set tDoc = ""
	Try { Set tDoc = {}.%FromJSON(tStream) } Catch ex { Set tDoc = "" }
	Quit:'$IsObject(tDoc) ""
	Quit:'$IsObject(tDoc.scenarios) ""
	Quit tDoc.scenarios
}

ClassMethod FindScenario(pId As %String) As %DynamicObject
{
	Set tList = ..LoadScenarios()
	Quit:'$IsObject(tList) ""
	Set tIter = tList.%GetIterator()
	While tIter.%GetNext(.tKey, .tScenario) {
		If tScenario.id = pId { Quit }
		Set tScenario = ""
	}
	Quit tScenario
}

/// Copies the scenario's shipped files into the inbox in order, earlier results first, through the staging
/// folder and a rename. Only files named in the scenario file are ever written; the request text is never used.
/// pControlIds returns the case ids of the messages written, as a %DynamicArray.
ClassMethod Drop(pScenario As %DynamicObject, Output pControlIds As %DynamicArray) As %Status
{
	Set pControlIds = []
	Set tSeq = $Increment(^Readback("flowSeq"))
	Set tN = 0
	Set tIter = pScenario.files.%GetIterator()
	While tIter.%GetNext(.tKey, .tName) {
		// A scenario names a file of the shipped samples: a plain name, or one folder (generated or demo) and a plain name.
		If tName '? .1(1"generated/",1"demo/")1.(1AN,1"-",1".",1"_") { Quit }
		If tName [ ".." { Quit }
		Set tN = tN + 1
		Set tSource = ##class(%File).NormalizeFilename(tName, ..SampleDir())
		If '##class(%File).Exists(tSource) { Quit }
		Set tTarget = "flow-"_$Translate($Justify(tSeq, 8), " ", "0")_"-"_$Translate($Justify(tN, 2), " ", "0")_"-"_$Piece(tName, "/", $Length(tName, "/"))
		Set tStaging = ##class(%File).NormalizeFilename(tTarget, ..Staging())
		Set tFinal = ##class(%File).NormalizeFilename(tTarget, ..Inbox())
		If '##class(%File).CopyFile(tSource, tStaging) { Quit }
		If '##class(%File).Rename(tStaging, tFinal) { Quit }
		Do pControlIds.%Push(..ControlIdOfFile(tFinal))
		// Distinct modification times keep the file service's order the order written.
		Hang 0.05
	}
	If tN '= pScenario.files.%Size() { Quit $System.Status.Error(5001, "the scenario files could not all be written") }
	Quit $$$OK
}

/// MSH-10 of an HL7 file, or empty.
ClassMethod ControlIdOfFile(pFile As %String) As %String
{
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Set tSC = tStream.LinkToFile(pFile)
	Quit:$System.Status.IsError(tSC) ""
	Set tHead = tStream.Read(400)
	Set tMsh = $Piece($Translate(tHead, $Char(13,10), $Char(10,10)), $Char(10), 1)
	Quit $Piece(tMsh, "|", 10)
}

// ----------------------------------------------------------------------------------------------------------
// The read-back task view
// ----------------------------------------------------------------------------------------------------------

/// The structured content of the read-back task of one decision for the signed-in person, or "" when the decision
/// is not a read-back one. A case id can be decided more than once (the same sample sent twice), so the view is keyed
/// by the decision, never by the case id. Carries the synthetic patient identifier: it is the only view that does,
/// because the person must know whose value they are reading back.
ClassMethod TaskView(pDecisionId As %String, pUser As %String) As %DynamicObject
{
	Quit:(pDecisionId '? 1.N) ""
	Set tTrace = ##class(Readback.Trace.Decision).%OpenId(pDecisionId)
	Quit:'$IsObject(tTrace) ""
	Quit:tTrace.Route'="readback" ""
	Set pControlId = tTrace.MessageControlId
	&sql(SELECT TOP 1 ID INTO :tLabId FROM Readback_Msg.LabResult WHERE MessageControlId = :pControlId ORDER BY ID DESC)
	Quit:SQLCODE'=0 ""
	Set tLab = ##class(Readback.Msg.LabResult).%OpenId(tLabId)
	Quit:'$IsObject(tLab) ""
	Set tWhy = ##class(Readback.Trace.Rebuild).ExplainRecord(tTrace)
	Set tAssigned = ..AssignedTo(tTrace.TaskId)
	Set tDone = (tTrace.ConfirmedAt '= "")
	Set tView = {}
	Set tView.controlId = pControlId
	Set tView.decisionId = +tTrace.%Id()
	Set tView.patientId = tLab.PatientId
	Set tView.analyteCode = tLab.AnalyteCode
	Set tView.analyteName = ..AnalyteName(pControlId)
	Set tView.valueText = tLab.ValueText
	Set tView.unit = tLab.Unit
	Set tView.convertedValue = tTrace.ConvertedValue
	Set tView.convertedUnit = tTrace.ConvertedUnit
	Set tView.reason = ##class(Readback.Config.Mode).Redact($Select(tWhy.ok:tWhy.reason, 1:""))
	Set tView.floorNote = ##class(Readback.Config.Mode).Redact(tTrace.FloorNote)
	Set tView.mode = tTrace.Mode
	Set tView.taskId = tTrace.TaskId
	Set tView.assignedTo = tAssigned
	If tTrace.SchemaValid {
		Set tAgent = {"decision":(tTrace.AgentDecision), "severity":(tTrace.AgentSeverity), "confidence":(tTrace.AgentConfidence), "rationale":(##class(Readback.Config.Mode).Redact(tTrace.Rationale))}
		Set tAgent.evidence = ..EvidenceList(tTrace.Evidence)
		Set tView.agent = tAgent
	} Else {
		Set tView.agentAbsent = {"failureKind":(tTrace.FailureKind), "failureReason":(##class(Readback.Config.Mode).Redact(tTrace.FailureReason))}
	}
	Set tTaskId = tTrace.TaskId
	&sql(SELECT COUNT(*) INTO :tAttempts FROM Readback_Trace.ReadbackAttempt WHERE TaskId = :tTaskId)
	Set tView.attemptCount = +$Get(tAttempts)
	If tView.attemptCount > 0 {
		&sql(SELECT TOP 1 Matched, AttemptedAt INTO :tMatched, :tAt FROM Readback_Trace.ReadbackAttempt WHERE TaskId = :tTaskId ORDER BY ID DESC)
		If SQLCODE = 0 {
			Set tLast = {"attemptedAt":($Get(tAt))}
			Do tLast.%Set("matched", ''$Get(tMatched), "boolean")
			Set tView.lastAttempt = tLast
		}
	}
	Set tState = {"state":($Select(tDone:"completed", 1:"open"))}
	If tDone { Set tState.confirmedBy = tTrace.ConfirmedBy, tState.confirmedAt = tTrace.ConfirmedAt }
	Set tView.state = tState.state
	If tDone { Set tView.confirmedBy = tTrace.ConfirmedBy, tView.confirmedAt = tTrace.ConfirmedAt }
	Do tView.%Set("canConfirm", (('tDone) && (tAssigned '= "") && (tAssigned = pUser)), "boolean")
	Quit tView
}

/// The evidence the agent cited, stored as one text, as a list of its items.
ClassMethod EvidenceList(pText As %String) As %DynamicArray
{
	Set tList = []
	Quit:pText="" tList
	Set tParsed = ""
	Try { Set tParsed = [].%FromJSON(pText) } Catch ex { Set tParsed = "" }
	Quit:$IsObject(tParsed) tParsed
	For i = 1:1:$Length(pText, ",") {
		Set tItem = $ZStrip($Piece(pText, ",", i), "<>W")
		Do:tItem'="" tList.%Push(tItem)
	}
	Quit tList
}

}
