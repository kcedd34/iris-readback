/// The synthetic message generator that runs inside IRIS with Embedded Python. That its text equals the text of the command line
/// generator for the same seed is proved end to end by tests/e2e/generator_check.py; these tests hold what can be held inside.
Class Readback.Test.GeneratorTest Extends %UnitTest.TestCase
{

Method TestAMessageIsMadeByPython()
{
	Set tText = ##class(Readback.Demo.Generator).Message("evaluation", 2026, 240, "RB2026-00219")
	Do $$$AssertTrue(tText '= "", "the Python method returns a message")
	Do $$$AssertEquals($Extract(tText, 1, 3), "MSH", "it is an HL7 message")
	Set tMsh = $Piece(tText, $Char(13), 1)
	Do $$$AssertEquals($Piece(tMsh, "|", 9), "ORU^R01", "it is an ORU^R01")
	Do $$$AssertEquals($Piece(tMsh, "|", 10), "RB2026-00219", "its control id is the one asked for")
	Do $$$AssertTrue(tText [ "Potassium", "it is the potassium result")
	Do $$$AssertTrue(tText [ "SYN", "the patient is synthetic")
}

Method TestTheSameArgumentsGiveTheSameText()
{
	Set tA = ##class(Readback.Demo.Generator).Message("samples", 42, 25, "RB42-00004H1")
	Set tB = ##class(Readback.Demo.Generator).Message("samples", 42, 25, "RB42-00004H1")
	Do $$$AssertTrue(tA '= "", "an earlier result of a patient is made")
	Do $$$AssertEquals(tA, tB, "generation is deterministic")
	Do $$$AssertTrue(##class(Readback.Demo.Generator).Message("samples", 43, 25, "RB42-00004H1") = "", "another seed has no such message")
}

Method TestArgumentsThatAreNotAcceptableMakeNothing()
{
	Do $$$AssertEquals(##class(Readback.Demo.Generator).Message("nosuchprofile", 42, 25, "RB42-00004"), "", "an unknown profile")
	Do $$$AssertEquals(##class(Readback.Demo.Generator).Message("samples", "x", 25, "RB42-00004"), "", "a seed that is not a number")
	Do $$$AssertEquals(##class(Readback.Demo.Generator).Message("samples", 42, 100000, "RB42-00004"), "", "a count over the limit")
	Do $$$AssertEquals(##class(Readback.Demo.Generator).Message("samples", 42, 25, "../../etc/passwd"), "", "a path in place of an id")
	Do $$$AssertEquals(##class(Readback.Demo.Generator).Message("samples", 42, 25, "RB42-99999"), "", "an id that is not in the dataset")
}

Method TestWriteUniqueTextGivesEachSubmissionItsOwnId()
{
	Set tText = ##class(Readback.Demo.Generator).Message("evaluation", 2026, 240, "RB2026-00219")
	Set tFile = ##class(%File).TempFilename("hl7")
	Set tA = ##class(Readback.API.Flow).WriteUniqueText(tText, tFile, 71)
	Set tB = ##class(Readback.API.Flow).WriteUniqueText(tText, tFile, 72)
	Do $$$AssertEquals(tA, "RB2026-00219-S71", "the first submission's id")
	Do $$$AssertEquals(tB, "RB2026-00219-S72", "the second submission's id differs")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId(tA), "RB2026-00219", "the recording is found through the base id")
	Do $$$AssertEquals(##class(Readback.API.Flow).WriteUniqueText("not a message", tFile, 1), "", "a text that is not a message writes nothing")
	Do ##class(%File).Delete(tFile)
}

}
