/// Cost from the price table: hand-computed values, and never zero for an unknown price.
Class Readback.Test.CostTest Extends %UnitTest.TestCase
{

Method OnAfterAllTests() As %Status
{
	Quit ##class(Readback.Config.Loader).LoadAll()
}

ClassMethod AddPrice(pModel As %String, pIn As %String, pOut As %String)
{
	Set tPrice = ##class(Readback.Config.Price).%New()
	Set tPrice.Model = pModel, tPrice.InputPerMillion = pIn, tPrice.OutputPerMillion = pOut, tPrice.PriceDate = +$Horolog
	Do tPrice.%Save()
}

Method TestKnownModelMatchesHandComputation()
{
	Do ##class(Readback.Config.Price).%KillExtent()
	Do ..AddPrice("m-known", 2.5, 10)
	Set tCost = ##class(Readback.Config.Cost).Compute("m-known", 1000, 500, .tKnown)
	Do $$$AssertEquals(tKnown, 1, "the cost is known")
	Do $$$AssertEquals(tCost, 0.0075, "1000 in at 2.5 and 500 out at 10 per million is 0.0075")
	Set tCost = ##class(Readback.Config.Cost).Compute("m-known", 0, 0, .tKnown)
	Do $$$AssertEquals(tKnown, 1, "zero tokens with a known price is a known cost")
	Do $$$AssertEquals(tCost, 0, "and costs nothing")
}

Method TestUnknownModelIsUnknownNotZero()
{
	Do ##class(Readback.Config.Price).%KillExtent()
	Do ..AddPrice("m-known", 2.5, 10)
	Set tCost = ##class(Readback.Config.Cost).Compute("m-missing", 1000, 500, .tKnown)
	Do $$$AssertEquals(tKnown, 0, "a model absent from the table has an unknown cost")
	Do $$$AssertEquals(tCost, "", "the cost is empty, never zero")
}

Method TestNullPricesAreUnknown()
{
	Do ##class(Readback.Config.Price).%KillExtent()
	Do ..AddPrice("m-null", "", "")
	Set tCost = ##class(Readback.Config.Cost).Compute("m-null", 1000, 500, .tKnown)
	Do $$$AssertEquals(tKnown, 0, "empty prices mean the cost is unknown")
	Do $$$AssertEquals(tCost, "", "and the cost is empty")
	Do ##class(Readback.Config.Price).%KillExtent()
	Do ..AddPrice("m-half", 2.5, "")
	Do ##class(Readback.Config.Cost).Compute("m-half", 1000, 500, .tKnown)
	Do $$$AssertEquals(tKnown, 0, "one missing price is enough to make the cost unknown")
}

Method TestEmptyModelIsUnknown()
{
	Do ##class(Readback.Config.Cost).Compute("", 1000, 500, .tKnown)
	Do $$$AssertEquals(tKnown, 0, "no model name means no known price")
}

}
