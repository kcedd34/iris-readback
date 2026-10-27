/// Cost of a call from the price table. The platform does not report cost.
Class Readback.Config.Cost
{

/// Returns the cost in USD, or "" with pKnown 0 when the model has no price or an incomplete price.
ClassMethod Compute(pModel As %String, pInputTokens As %Integer, pOutputTokens As %Integer, Output pKnown As %Boolean) As %Numeric
{
	Set pKnown = 0
	Quit:pModel="" ""
	Quit:'##class(Readback.Config.Price).ModelIdxExists(pModel, .tId) ""
	Set tPrice = ##class(Readback.Config.Price).%OpenId(tId)
	Quit:'$IsObject(tPrice) ""
	Quit:(tPrice.InputPerMillion="")||(tPrice.OutputPerMillion="") ""
	Set pKnown = 1
	Quit (+pInputTokens * tPrice.InputPerMillion / 1000000) + (+pOutputTokens * tPrice.OutputPerMillion / 1000000)
}

}
