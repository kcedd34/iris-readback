/// The policy file: validated line by line, versioned by its hash, and the table follows it exactly.
Class Readback.Test.PolicyIndexTest Extends %UnitTest.TestCase
{

Parameter DIR = "/tmp/readback-policytest";

Method OnAfterAllTests() As %Status
{
	Do ##class(%File).RemoveDirectoryTree(..#DIR)
	Quit $$$OK
}

ClassMethod Write(pName As %String, pLines As %List) As %String
{
	Do ##class(%File).CreateDirectoryChain(..#DIR)
	Set tFile = ..#DIR_"/"_pName
	Set tStream = ##class(%Stream.FileCharacter).%New()
	Do tStream.LinkToFile(tFile)
	For i = 1:1:$ListLength(pLines) { Do tStream.WriteLine($List(pLines, i)) }
	Do tStream.%Save()
	Quit tFile
}

ClassMethod Passage(pId As %String, pText As %String = "Some policy text.") As %String
{
	Quit "{""id"":"""_pId_""",""source"":""doc"",""title"":""Title"",""text"":"""_pText_"""}"
}

Method TestShippedFileIsValid()
{
	Set tSC = ##class(Readback.Retrieval.Policy).Read(, .tPassages, .tVersion)
	Do $$$AssertStatusOK(tSC, "the shipped file reads")
	Do $$$AssertTrue(tPassages.%Size() >= 15, "it holds the passages: "_tPassages.%Size())
	Do $$$AssertEquals($Length(tVersion), 16, "the version is a 16-character hash")
}

Method TestMalformedLinesAreRejectedWithTheLine()
{
	Set tFile = ..Write("bad1.jsonl", $ListBuild(..Passage("a"), "this is not json"))
	Set tSC = ##class(Readback.Retrieval.Policy).Read(tFile)
	Do $$$AssertStatusNotOK(tSC, "a line that is not JSON is rejected")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["line 2", "the message names the line")
	Set tFile = ..Write("bad2.jsonl", $ListBuild(..Passage("a"), "{""id"":""b"",""source"":""doc"",""title"":""T""}"))
	Set tSC = ##class(Readback.Retrieval.Policy).Read(tFile)
	Do $$$AssertStatusNotOK(tSC, "a line missing a field is rejected")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC)["'text'", "the message names the field")
	Set tFile = ..Write("bad3.jsonl", $ListBuild(..Passage("a"), ..Passage("a")))
	Do $$$AssertStatusNotOK(##class(Readback.Retrieval.Policy).Read(tFile), "a repeated id is rejected")
	Set tFile = ..Write("bad4.jsonl", $ListBuild(""))
	Do $$$AssertStatusNotOK(##class(Readback.Retrieval.Policy).Read(tFile), "an empty file is rejected")
	Do $$$AssertStatusNotOK(##class(Readback.Retrieval.Policy).Read(..#DIR_"/nope.jsonl"), "a missing file is rejected")
}

Method TestVersionIsTheHashOfTheFile()
{
	Set tA = ..Write("v1.jsonl", $ListBuild(..Passage("a"), ..Passage("b")))
	Do ##class(Readback.Retrieval.Policy).Read(tA, , .tV1)
	Do ##class(Readback.Retrieval.Policy).Read(tA, , .tV1b)
	Do $$$AssertEquals(tV1, tV1b, "the same file gives the same version")
	Set tB = ..Write("v2.jsonl", $ListBuild(..Passage("a"), ..Passage("b", "A changed text.")))
	Do ##class(Readback.Retrieval.Policy).Read(tB, , .tV2)
	Do $$$AssertTrue(tV1'=tV2, "a changed passage changes the version")
}

Method TestReindexEmptiesTheTableFirst()
{
	Set tEngine = ##class(Readback.Retrieval.Engine).%New()
	Do tEngine.Build()
	If '$$$AssertTrue(tEngine.Available, "the engine is available (model cache of the image): "_tEngine.Reason) { Quit }
	Set tFile = ..Write("small.jsonl", $ListBuild(..Passage("only-one", "Potassium critical value policy."), ..Passage("only-two", "Sample hemolysis policy.")))
	Set tSC = ##class(Readback.Retrieval.Policy).EnsureIndexed(tEngine, tFile, .tVersion)
	Do $$$AssertStatusOK(tSC, "a changed file is indexed")
	Do $$$AssertEquals(tEngine.PolicyRows(), 2, "only the two passages of the new file are in the table: no stale passage survives")
	&sql(SELECT COUNT(*) INTO :tStale FROM Readback_Retrieval.PolicyVec WHERE source = 'crit-potassium')
	Do $$$AssertEquals(tStale, 0, "a passage of the previous file is gone")
	// Restore the shipped policy.
	Set tSC = ##class(Readback.Retrieval.Policy).EnsureIndexed(tEngine, , .tReal)
	Do $$$AssertStatusOK(tSC, "the shipped policy is indexed again")
	Do $$$AssertTrue(tEngine.PolicyRows() >= 15, "all shipped passages are back")
	Do $$$AssertEquals(##class(Readback.Retrieval.Policy).StoredVersion(), tReal, "the stored version is the shipped hash")
}

}
