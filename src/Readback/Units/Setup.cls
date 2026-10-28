/// Registers the Java unit conversion component with the PEX framework. Idempotent: it registers again only
/// when the jar changed. Needs the jar built by java/build.sh.
Class Readback.Units.Setup
{

Parameter Jar = "/opt/readback/java/build/readback-units.jar";

Parameter Ucum = "/opt/readback/java/lib/ucum-1.0.9.jar";

Parameter PexJar = "/usr/irissys/dev/java/lib/1.8/intersystems-pex-1.0.0-shaded.jar";

Parameter ProxyClass = "Readback.Units.JavaOperation";

ClassMethod EnsureComponent() As %Status
{
	If '##class(%File).Exists(..#Jar) { Quit $System.Status.Error(5001, "unit conversion component not built: "_..#Jar_" is missing") }
	Set tStamp = ##class(%File).GetFileDateModified(..#Jar)
	If ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass) && ($Get(^Readback("unitsJar")) = tStamp) { Quit $$$OK }
	Set tPath = ..#Jar_":"_..#Ucum_":"_..#PexJar
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
