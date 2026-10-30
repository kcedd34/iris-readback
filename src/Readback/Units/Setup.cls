/// Registers the Java unit conversion component with the PEX framework. Idempotent: it registers again only
/// when the jar changed. Needs the jar built by java/build.sh.
Class Readback.Units.Setup
{

/// The jar built from java/ and the vendored UCUM library, under the product's Java folder.
ClassMethod Jar() As %String
{
	Quit ##class(Readback.Config.Paths).JavaDir()_"/build/readback-units.jar"
}

ClassMethod Ucum() As %String
{
	Quit ##class(Readback.Config.Paths).JavaDir()_"/lib/ucum-1.0.9.jar"
}

Parameter PexJar = "/usr/irissys/dev/java/lib/1.8/intersystems-pex-1.0.0-shaded.jar";

Parameter ProxyClass = "Readback.Units.JavaOperation";

ClassMethod EnsureComponent() As %Status
{
	If '##class(%File).Exists(..Jar()) { Quit $System.Status.Error(5001, "unit conversion component not built: "_..Jar()_" is missing") }
	Set tStamp = ##class(%File).GetFileDateModified(..Jar())
	If ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass) && ($Get(^Readback("unitsJar")) = tStamp) { Quit $$$OK }
	Set tPath = ..Jar()_":"_..Ucum()_":"_..#PexJar
	Set tSC = ##class(EnsLib.PEX.Utils).RegisterComponent("com.readback.units.UnitsOperation", "%Java Server", tPath, 1, ..#ProxyClass, 1)
	If $System.Status.IsOK(tSC) { Set ^Readback("unitsJar") = tStamp }
	Quit tSC
}

/// True when the proxy class of the component exists, for the status endpoint.
ClassMethod IsRegistered() As %Boolean
{
	Quit ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass)
}

}
