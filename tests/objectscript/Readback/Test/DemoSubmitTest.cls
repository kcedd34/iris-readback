/// A demo submission is a new case every time: its case id carries a suffix of its own, the rest of the message is the
/// sample's, and the recording of the sample is still found through the base id.
Class Readback.Test.DemoSubmitTest Extends %UnitTest.TestCase
{

Method TestBaseIdTakesOffOnlyTheSubmissionSuffix()
{
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId("RBSAMPLE0001-S12"), "RBSAMPLE0001")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId("RB2026-00007H1-S3"), "RB2026-00007H1")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId("RB2026-00007"), "RB2026-00007")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId("RB-S-ample"), "RB-S-ample")
	Do $$$AssertEquals(##class(Readback.Replay.Recording).BaseId(""), "")
}

Method TestTheSameSampleSentTwiceGetsTwoCaseIds()
{
	Set tSource = ##class(%File).NormalizeFilename("demo/RB2026-00007.hl7", ##class(Readback.API.Flow).SampleDir())
	Do $$$AssertTrue(##class(%File).Exists(tSource), "the shipped sample exists")
	Set tA = ##class(%File).TempFilename("hl7"), tB = ##class(%File).TempFilename("hl7")
	Set tIdA = ##class(Readback.API.Flow).WriteUnique(tSource, tA, 41)
	Set tIdB = ##class(Readback.API.Flow).WriteUnique(tSource, tB, 42)
	Do $$$AssertEquals(tIdA, "RB2026-00007-S41")
	Do $$$AssertEquals(tIdB, "RB2026-00007-S42")
	Do $$$AssertEquals(##class(Readback.API.Flow).ControlIdOfFile(tA), tIdA)
	Do $$$AssertEquals(##class(Readback.API.Flow).ControlIdOfFile(tB), tIdB)
	// Only MSH-10 changed: the original message is the new one with the id put back.
	Set tOrig = ##class(%Stream.FileBinary).%New(), tNew = ##class(%Stream.FileBinary).%New()
	Do tOrig.LinkToFile(tSource), tNew.LinkToFile(tA)
	Set tText = tNew.Read(tNew.Size)
	Do $$$AssertEquals($Replace(tText, "RB2026-00007-S41", "RB2026-00007"), tOrig.Read(tOrig.Size))
	Do ##class(%File).Delete(tA), ##class(%File).Delete(tB)
}

Method TestAFileThatIsNotAnHl7MessageIsNotWritten()
{
	Set tTmp = ##class(%File).TempFilename("txt")
	Set tS = ##class(%Stream.FileBinary).%New()
	Do tS.LinkToFile(tTmp), tS.Write("not hl7"), tS.%Save()
	Do $$$AssertEquals(##class(Readback.API.Flow).WriteUnique(tTmp, tTmp_".out", 1), "")
	Do ##class(%File).Delete(tTmp)
}

}
