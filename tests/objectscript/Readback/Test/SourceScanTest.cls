/// A final decision may only be created by Readback.Triage.Composer.
Class Readback.Test.SourceScanTest Extends %UnitTest.TestCase
{

Method TestOnlyTheComposerCreatesAFinalDecision()
{
	Set tOffenders = "", tScanned = 0
	Set tStmt = ##class(%SQL.Statement).%New()
	Do tStmt.%Prepare("SELECT parent, Name FROM %Dictionary.CompiledMethod WHERE parent LIKE 'Readback.%' AND parent NOT LIKE 'Readback.Test.%' AND parent <> 'Readback.Triage.Composer' AND parent <> 'Readback.Triage.FinalDecision'")
	Set tRS = tStmt.%Execute()
	While tRS.%Next() {
		Set tMethod = ##class(%Dictionary.CompiledMethod).%OpenId(tRS.%Get("parent")_"||"_tRS.%Get("Name"))
		Continue:'$IsObject(tMethod)
		Set tScanned = tScanned + 1
		Set tCode = tMethod.Implementation.Read(1000000)
		If (tCode [ "FinalDecision") && ((tCode [ "FinalDecision).%New") || (tCode [ "FinalDecision).%OpenId")) {
			Set tOffenders = tOffenders_" "_tRS.%Get("parent")_"::"_tRS.%Get("Name")
		}
	}
	Do $$$AssertTrue(tScanned > 10, "methods were scanned ("_tScanned_")")
	Do $$$AssertEquals(tOffenders, "", "no class other than the composer creates a FinalDecision:"_tOffenders)
}

}
