/// The Visual Trace message of a tool call is a side channel: it never throws, a failure to send never reaches the record
/// of the investigation, the replay sends the recorded calls in order labelled replay, and no argument line names a patient.
Class Readback.Test.TraceEmitTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Kill ^||Readback.TraceFaults, ^||Readback.AuditFaults
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^||Readback.TraceFaults, ^||Readback.AuditFaults
	Quit $$$OK
}

ClassMethod Calls() As %String
{
	Quit [{"tool":"get_patient_history","arguments":"{\"limit\": 3}","result":"{\"found\":2}","status":"ok","reason":"","durationMs":62},{"tool":"get_delta_assessment","arguments":"{}","result":"{\"floorVerdict\":\"critical by change\"}","status":"ok","reason":"","durationMs":0},{"tool":"search_policy","arguments":"{\"query\": \"potassium 8.7\"}","result":"","status":"refused","reason":"scope","durationMs":0}].%ToJSON()
}

Method TestAMissingHostIsNotAnError()
{
	Kill ^||Readback.TraceFaults
	Do ##class(Readback.Agent.TraceEmit).Send("", "live", "c1", 1, "get_patient_history", "ok", 5, "{}", "answered")
	Do $$$AssertEquals($Get(^||Readback.TraceFaults), "", "no host: nothing sent, nothing counted, nothing raised")
}

Method TestAFailedSendIsCountedApartAndNeverAnAuditFault()
{
	Kill ^||Readback.TraceFaults, ^||Readback.AuditFaults
	Set tHost = ##class(Readback.Test.FakeHost).%New("error")
	Do ##class(Readback.Agent.TraceEmit).Send(tHost, "live", "c1", 1, "get_patient_history", "ok", 5, "{}", "answered")
	Do $$$AssertEquals(+$Get(^||Readback.TraceFaults), 1, "the failure is counted in the trace's own variable")
	Do $$$AssertEquals(+$Get(^||Readback.AuditFaults), 0, "and is not an audit fault, so the investigation record does not change")
}

Method TestAHostThatRaisesIsSwallowed()
{
	Kill ^||Readback.TraceFaults, ^||Readback.AuditFaults
	Set tHost = ##class(Readback.Test.FakeHost).%New("raise")
	Do ##class(Readback.Agent.TraceEmit).Send(tHost, "live", "c1", 1, "get_patient_history", "ok", 5, "{}", "answered")
	Do $$$AssertEquals(+$Get(^||Readback.TraceFaults), 1, "a host that raises is counted, not propagated")
	Do $$$AssertEquals(+$Get(^||Readback.AuditFaults), 0, "and is not an audit fault")
}

Method TestTheAuditPolicyKeepsAnEntryWhenTheSendFails()
{
	Kill ^||Readback.AuditLog, ^||Readback.AuditSeq, ^||Readback.AuditFaults, ^||Readback.TraceFaults
	Set %ReadbackHost = ##class(Readback.Test.FakeHost).%New("error")
	Do ##class(Readback.Governance.AuditPolicy).Record({"name":"get_delta_assessment","arguments":"{}"}, "ok", "{""floorVerdict"":""none""}", "", 3)
	Kill %ReadbackHost
	Do $$$AssertEquals(##class(Readback.Governance.AuditPolicy).Entries().%Size(), 1, "the audit entry is kept")
	Do $$$AssertEquals(+$Get(^||Readback.AuditFaults), 0, "a failed trace message is not an audit fault")
	Do $$$AssertEquals(+$Get(^||Readback.TraceFaults), 1, "it is counted as a trace fault")
	Do ##class(Readback.Governance.AuditPolicy).Reset()
}

Method TestTheReplaySendsTheRecordedCallsInOrderLabelledReplay()
{
	Set tHost = ##class(Readback.Test.FakeHost).%New("ok")
	Do ##class(Readback.Agent.TraceEmit).Replay(tHost, "c1", ..Calls())
	Do $$$AssertEquals(tHost.Sent.%Size(), 3, "one message per recorded call")
	Do $$$AssertEquals(tHost.Sent.%Get(0).tool_"/"_tHost.Sent.%Get(1).tool_"/"_tHost.Sent.%Get(2).tool, "get_patient_history/get_delta_assessment/search_policy", "in the recorded order")
	Do $$$AssertEquals(tHost.Sent.%Get(0).seq_tHost.Sent.%Get(1).seq_tHost.Sent.%Get(2).seq, "123", "numbered from 1")
	Do $$$AssertEquals(tHost.Sent.%Get(0).mode, "replay", "labelled replay")
	Do $$$AssertEquals(tHost.Sent.%Get(2).status, "refused", "a refused call keeps its status")
	Do $$$AssertEquals(tHost.Sent.%Get(0).target, "Readback.Agent.ToolTrace", "to the trace operation")
	Do $$$AssertEquals(tHost.Sent.%Get(0).durationMs, 62, "with the recorded time")
}

Method TestTheReplayWithTheOperationOffDoesNotRaise()
{
	Kill ^||Readback.TraceFaults
	Set tHost = ##class(Readback.Test.FakeHost).%New("error")
	Do ##class(Readback.Agent.TraceEmit).Replay(tHost, "c1", ..Calls())
	Do $$$AssertEquals(+$Get(^||Readback.TraceFaults), 3, "each unsent step is counted, none raised")
}

Method TestAnEmptyOrBrokenRecordingSendsNothing()
{
	Set tHost = ##class(Readback.Test.FakeHost).%New("ok")
	Do ##class(Readback.Agent.TraceEmit).Replay(tHost, "c1", "")
	Do ##class(Readback.Agent.TraceEmit).Replay(tHost, "c1", "not json")
	Do $$$AssertEquals(tHost.Sent.%Size(), 0, "nothing sent, nothing raised")
}

Method TestTheArgumentLineNeverNamesAPatient()
{
	Set tLine = ##class(Readback.Tools.Summary).Args("{""limit"":3,""patient_id"":""SYN9100001"",""caseId"":""X1"",""mrn"":""123"",""name"":""A B"",""subjectId"":""s""}")
	Do $$$AssertEquals(tLine, "limit=3", "only the harmless argument is kept: "_tLine)
}

Method TestTheArgumentLineIsShortAndSurvivesBadInput()
{
	Set tLine = ##class(Readback.Tools.Summary).Args("{""query"":"""_$Justify("", 300)_"""}")
	Set tShort = ($Length(tLine) < 151)
	Do $$$AssertTrue(tShort, "the line is at most 150 characters")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Args("not json"), "", "not JSON gives an empty line")
	Do $$$AssertEquals(##class(Readback.Tools.Summary).Args(""), "", "nothing gives an empty line")
}

}
