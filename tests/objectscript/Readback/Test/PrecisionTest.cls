/// A converted value is shown with the clinical precision of its analyte, with the decimals kept (26.0, not 26).
Class Readback.Test.PrecisionTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

Method TestGlucoseInMmolHasOneDecimal()
{
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", 26.0312), "26.0")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", "25.96"), "26.0")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", 4.55555), "4.6")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", 0.54), "0.5")
	// A conversion carries more digits than a number holds exactly; it is still a number.
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", "26.032993627744843358"), "26.0")
}

Method TestEachAnalyteKeepsItsOwnPrecision()
{
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2951-2", 150.4), "150")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("718-7", 8.04), "8.0")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2823-3", 6.94), "6.9")
}

Method TestWhatCannotBeRoundedComesBackAsGiven()
{
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("0000-0", 1.2345), 1.2345, "an analyte that is not in the table")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", ""), "")
	Do $$$AssertEquals(##class(Readback.Config.Analyte).Round("2345-7", "not a number"), "not a number")
}

}
