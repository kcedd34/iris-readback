/// The read-only views of the flow panel and the read-back task screen (Readback.API.Flow): the snapshot, the cursor,
/// the derivation of in flight and waiting, the failure kinds shown as recorded, the task view, and the guards of
/// the submit. Rows are written directly under case ids that start with FLW and removed afterwards.
Class Readback.Test.FlowTest Extends %UnitTest.TestCase
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
	&sql(DELETE FROM Readback_Trace.Decision WHERE MessageControlId LIKE 'FLW%')
	&sql(DELETE FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'FLW%')
	&sql(DELETE FROM Readback_Trace.ReadbackAttempt WHERE TaskId LIKE 'FLW%')
}

ClassMethod Lab(pId As %String, pCode As %String = "2823-3", pValue As %String = "6.9", pUnit As %String = "mmol/L", pReceived As %String = "") As Readback.Msg.LabResult
{
	Set tLab = ##class(Readback.Msg.LabResult).%New()
	Set tLab.MessageControlId = pId, tLab.PatientId = "SYN9900001", tLab.AnalyteCode = pCode
	Set tLab.ValueText = pValue, tLab.ValueNumeric = pValue, tLab.Unit = pUnit, tLab.Source = "file", tLab.AgeYears = 50
	Set:pReceived'="" tLab.ReceivedAt = pReceived
	Do tLab.%Save()
	Quit tLab
}

ClassMethod Decide(pId As %String, pRoute As %String = "readback", pFailureKind As %String = "", pTaskId As %String = "") As Readback.Trace.Decision
{
	Set tD = ##class(Readback.Trace.Decision).%New()
	Set tD.MessageControlId = pId, tD.SessionId = 1, tD.Mode = "replay", tD.Route = pRoute
	Set tD.FloorSeverity = 3, tD.FinalSeverity = 3, tD.AgentCalled = 1, tD.TaskId = pTaskId
	If pFailureKind = "" {
		Set tD.SchemaValid = 1, tD.AgentDecision = "CRITICAL", tD.AgentSeverity = 3, tD.AgentConfidence = "high"
		Set tD.Rationale = "Potassium above the limit.", tD.Evidence = "current-result, crit-potassium"
	} Else {
		Set tD.SchemaValid = 0, tD.FailureKind = pFailureKind, tD.FailureReason = "no answer within 30 seconds"
	}
	Do tD.%Save()
	Quit tD
}

ClassMethod HasControlId(pList As %DynamicArray, pId As %String) As %Boolean
{
	Set tIter = pList.%GetIterator()
	While tIter.%GetNext(.tKey, .tItem) { Quit:tItem.controlId=pId }
	Quit $Select($IsObject($Get(tItem)):(tItem.controlId=pId), 1:0)
}

Method TestInFlightUntilDecided()
{
	Do ..Lab("FLW-A-1")
	Set tSnap = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertTrue(..HasControlId(tSnap.inFlight, "FLW-A-1"), "a stored result with no decision is in flight")
	Do ..Decide("FLW-A-1")
	Set tSnap = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertTrue('(..HasControlId(tSnap.inFlight, "FLW-A-1")), "once decided it is no longer in flight")
}

Method TestOldUndecidedNotInFlight()
{
	Do ..Lab("FLW-A-2", , , , "2020-01-01 00:00:00")
	Set tSnap = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertTrue('(..HasControlId(tSnap.inFlight, "FLW-A-2")), "a result received long ago and never decided is not in flight")
}

Method TestCursorBaselineAndPaging()
{
	Do ..Lab("FLW-B-1"), ..Lab("FLW-B-2"), ..Lab("FLW-B-3")
	Set tBase = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertEquals(tBase.decided.%Size(), 0, "no after: nothing in decided, the panel starts from now")
	Do $$$AssertEquals(tBase.cursor, ##class(Readback.API.Flow).MaxDecisionId(), "the cursor is the newest decision")
	Do ..Decide("FLW-B-1"), ..Decide("FLW-B-2", "review"), ..Decide("FLW-B-3", "readback", "timeout")
	Set tNew = ##class(Readback.API.Flow).Snapshot(tBase.cursor)
	Do $$$AssertEquals(tNew.decided.%Size(), 3, "the three new decisions come back, oldest first")
	Do $$$AssertEquals(tNew.decided.%Get(0).controlId, "FLW-B-1", "oldest first")
	Do $$$AssertEquals(tNew.decided.%Get(1).route, "review", "the recorded route")
	Do $$$AssertEquals(tNew.decided.%Get(2).failureKind, "timeout", "the recorded failure kind")
	Do $$$AssertEquals(tNew.cursor, ##class(Readback.API.Flow).MaxDecisionId(), "the cursor moves to the last returned")
	Set tAgain = ##class(Readback.API.Flow).Snapshot(tNew.cursor)
	Do $$$AssertEquals(tAgain.decided.%Size(), 0, "asking again with the new cursor returns nothing")
	Set tAll = ##class(Readback.API.Flow).Snapshot(0)
	Do $$$AssertTrue(tAll.decided.%Size() <= ##class(Readback.API.Flow).#MaxDecided, "a page is bounded")
}

Method TestWaitingAndConfirmed()
{
	Do ..Lab("FLW-C-1"), ..Lab("FLW-C-2")
	Set tOk = ..Decide("FLW-C-1")
	Set tFailed = ..Decide("FLW-C-2", "readback", "provider-error")
	Set tSnap = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertTrue(..HasControlId(tSnap.waiting, "FLW-C-1"), "a read-back decision with no confirmation is waiting")
	Do $$$AssertTrue(..HasControlId(tSnap.waiting, "FLW-C-2"), "a rule-critical case whose agent step failed still waits at read-back")
	Set tOk.ConfirmedBy = "communicator1", tOk.ConfirmedAt = $ZDateTime($ZTimeStamp, 3, 1, 3), tOk.ReadbackMatch = 1
	Do tOk.%Save()
	Set tSnap = ##class(Readback.API.Flow).Snapshot()
	Do $$$AssertTrue('(..HasControlId(tSnap.waiting, "FLW-C-1")), "a confirmed case leaves the waiting list")
	Do $$$AssertTrue(..HasControlId(tSnap.confirmed, "FLW-C-1"), "and appears among the recently confirmed, with who confirmed it")
	Do $$$AssertTrue(tSnap.waitingTotal >= 1, "the waiting total counts")
}

Method TestNoPatientIdNoKey()
{
	Do ..Lab("FLW-D-1")
	Set tD = ..Decide("FLW-D-1", "readback", "provider-error")
	Set tD.FailureReason = "provider said sk-abcdefghijklmnop1234 is invalid"
	Do tD.%Save()
	Set tJson = ##class(Readback.API.Flow).Snapshot(0).%ToJSON()
	Do $$$AssertTrue(tJson'["SYN99", "the flow snapshot carries no patient identifier")
	Do $$$AssertTrue(tJson'["sk-abcdefghijklmnop1234", "a key-shaped token in a recorded reason is redacted")
}

Method TestEvidenceIsAList()
{
	Set tList = ##class(Readback.API.Flow).EvidenceList("current-result, crit-potassium")
	Do $$$AssertEquals(tList.%Size(), 2, "two items")
	Do $$$AssertEquals(tList.%Get(1), "crit-potassium", "trimmed")
	Do $$$AssertEquals(##class(Readback.API.Flow).EvidenceList("").%Size(), 0, "empty stays empty")
	Do $$$AssertEquals(##class(Readback.API.Flow).EvidenceList("[""a"",""b""]").%Size(), 2, "a JSON array is kept")
}

Method TestTaskViewOpen()
{
	Do ..Lab("FLW-E-1")
	Set tD = ..Decide("FLW-E-1", "readback", "", "FLWTASK-1")
	Set tD.ConvertedValue = "6.9", tD.ConvertedUnit = "mmol/L"
	Do tD.%Save()
	Set tView = ##class(Readback.API.Flow).TaskView(tD.%Id(), "communicator1")
	Do $$$AssertEquals(tView.patientId, "SYN9900001", "the task view carries the synthetic patient identifier")
	Do $$$AssertEquals(tView.valueText, "6.9", "the value as received")
	Do $$$AssertEquals(tView.unit, "mmol/L", "the unit as received")
	Do $$$AssertEquals(tView.convertedUnit, "mmol/L", "the converted unit")
	Do $$$AssertEquals(tView.analyteName, "Potassium", "the analyte name")
	Do $$$AssertEquals(tView.agent.rationale, "Potassium above the limit.", "the agent rationale")
	Do $$$AssertEquals(tView.agent.evidence.%Size(), 2, "the cited evidence")
	Do $$$AssertEquals(tView.state, "open", "open")
	Do $$$AssertEquals(tView.attemptCount, 0, "no attempt yet")
	Do $$$AssertTrue('(tView.canConfirm), "nobody is assigned in this fixture, so nobody can confirm")
	Do $$$AssertTrue(tView.reason'="", "the recorded reason")
}

Method TestTaskViewFailedAndDone()
{
	Do ..Lab("FLW-F-1")
	Set tD = ..Decide("FLW-F-1", "readback", "timeout", "FLWTASK-2")
	Set tView = ##class(Readback.API.Flow).TaskView(tD.%Id(), "observer")
	Do $$$AssertTrue('(tView.%IsDefined("agent")), "no agent object when the agent step failed")
	Do $$$AssertEquals(tView.agentAbsent.failureKind, "timeout", "the failure kind is shown")
	Do $$$AssertTrue(tView.agentAbsent.failureReason'="", "and its reason")
	Set tD.ConfirmedBy = "communicator2", tD.ConfirmedAt = $ZDateTime($ZTimeStamp, 3, 1, 3), tD.ReadbackMatch = 1
	Do tD.%Save()
	Set tView = ##class(Readback.API.Flow).TaskView(tD.%Id(), "communicator2")
	Do $$$AssertEquals(tView.state, "completed", "completed")
	Do $$$AssertEquals(tView.confirmedBy, "communicator2", "who confirmed")
	Do $$$AssertTrue('(tView.canConfirm), "a completed task cannot be confirmed again")
}

Method TestTaskViewNoTask()
{
	Do ..Lab("FLW-G-1")
	Set tD = ..Decide("FLW-G-1", "review")
	Do $$$AssertEquals(##class(Readback.API.Flow).TaskView(tD.%Id(), "communicator1"), "", "a review decision has no read-back task view")
	Do $$$AssertEquals(##class(Readback.API.Flow).TaskView(999999999, "communicator1"), "", "an unknown decision has none")
	Do $$$AssertEquals(##class(Readback.API.Flow).TaskView("FLW-G-1", "communicator1"), "", "a case id is not a decision id")
}

Method TestScenariosAndDropGuards()
{
	Set tList = ##class(Readback.API.Flow).LoadScenarios()
	Do $$$AssertTrue($IsObject(tList) && (tList.%Size() >= 8), "the shipped scenario list loads")
	Do $$$AssertEquals(##class(Readback.API.Flow).FindScenario("no-such-scenario"), "", "an unknown scenario is not found")
	Set tFound = ##class(Readback.API.Flow).FindScenario("potassium-critical-value")
	Do $$$AssertTrue($IsObject(tFound) && (tFound.messages.%Size() = 1) && (tFound.generator.profile = "evaluation"), "a known scenario is found, with its generator and message ids")
	// A scenario whose message is not in the generated dataset, or whose arguments are not acceptable, writes nothing.
	Set tBad = {"id":"x", "generator":{"profile":"evaluation","seed":2026,"count":240}, "messages":["../../etc/passwd"]}
	Do $$$AssertTrue($System.Status.IsError(##class(Readback.API.Flow).Drop(tBad, .tIds)), "a path in place of a message id is refused")
	Set tBad2 = {"id":"x", "generator":{"profile":"nosuchprofile","seed":2026,"count":240}, "messages":["RB2026-00001"]}
	Do $$$AssertTrue($System.Status.IsError(##class(Readback.API.Flow).Drop(tBad2, .tIds)), "an unknown profile is refused")
	Set tBad3 = {"id":"x", "generator":{"profile":"evaluation","seed":2026,"count":240}, "messages":["RB2026-09999"]}
	Do $$$AssertTrue($System.Status.IsError(##class(Readback.API.Flow).Drop(tBad3, .tIds)), "a message that is not in the dataset is refused")
	Set tBad4 = {"id":"x", "files":["valid-oru-1.hl7"]}
	Do $$$AssertTrue($System.Status.IsError(##class(Readback.API.Flow).Drop(tBad4, .tIds)), "the old file form is not accepted any more")
}

}
