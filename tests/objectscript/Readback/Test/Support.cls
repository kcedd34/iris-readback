/// Helpers for end-to-end checks that need to change the running production. Not used by the product.
Class Readback.Test.Support
{

/// Changes a setting of an item in the running production and applies it.
/// pTarget is "Adapter" or "Host".
ClassMethod SetSetting(pItem As %String, pTarget As %String, pName As %String, pValue As %String) As %Status
{
	If pTarget = "Adapter" {
		Set tSC = ##class(Ens.Director).SetAdapterSettingValue(pItem, pName, pValue)
	} Else {
		Set tSC = ##class(Ens.Director).SetHostSettingValue(pItem, pName, pValue)
	}
	Quit:$System.Status.IsError(tSC) tSC
	Quit ##class(Ens.Director).UpdateProduction(30, 1)
}

}
