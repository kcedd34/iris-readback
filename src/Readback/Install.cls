/// The activation step of the IPM package. It does what the image's start script does for the product, on an instance
/// that is not the image: records where the package put the product's files, makes the working folders, builds the
/// unit conversion component, points the production at those folders, loads the configuration, and starts the production.
/// Idempotent: running it again leaves the same result. The IPM client itself is not part of this step.
Class Readback.Install
{

Parameter Production = "Readback.Production";

/// Runs every step and reports each one; returns an error status if a required step failed. The embedding model download
/// is optional: without network, retrieval reports itself unavailable and the rest still works.
ClassMethod Run(pHome As %String = "") As %Status
{
	Set tFailed = 0
	Try {
		If pHome = "" { Set pHome = $System.Util.ManagerDirectory()_"readback" }
		If $Extract(pHome, *) = "/" { Set pHome = $Extract(pHome, 1, *-1) }
		Set ^Readback("home") = pHome
		For tDir = pHome_"/in", pHome_"/archive", pHome_"/work" {
			If '##class(%File).DirectoryExists(tDir) { Do ##class(%File).CreateDirectoryChain(tDir) }
		}
		Set tFailed = tFailed + ..Report("units component built", ..BuildUnits(pHome), 1)
		Set tFailed = tFailed + ..Report("production settings", ..PointProduction(pHome), 1)
		Set tFailed = tFailed + ..Report("configuration loaded", ##class(Readback.Config.Loader).LoadAll(), 1)
		Set tFailed = tFailed + ..Report("units component registered", ##class(Readback.Units.Setup).EnsureComponent(), 1)
		Set tFailed = tFailed + ..Report("policy index", ##class(Readback.Retrieval.Engine).Prepare(), 0)
		Set tFailed = tFailed + ..Report("web application", ##class(Readback.API.Status).EnsureWebApp(), 1)
		Set tFailed = tFailed + ..Report("workflow roles", ##class(Readback.Workflow.Setup).EnsureRoles(), 1)
		Set tFailed = tFailed + ..Report("production started", ..Start(), 1)
	} Catch ex {
		Write "Readback install: stopped by an error: ", ex.DisplayString(), !
		Set tFailed = tFailed + 1
	}
	Quit $Select(tFailed: $System.Status.Error(5001, "Readback install: "_tFailed_" required step(s) failed"), 1: $$$OK)
}

/// Prints the outcome of one step; returns 1 when a required step failed, else 0.
ClassMethod Report(pStep As %String, pStatus As %Status, pRequired As %Boolean) As %Integer
{
	If $System.Status.IsOK(pStatus) { Write "Readback install: ", pStep, ": ok", ! Quit 0 }
	Write "Readback install: ", pStep, ": ", $Select(pRequired: "FAILED", 1: "skipped"), ": ", ##class(Readback.Config.Mode).Redact($System.Status.GetErrorText(pStatus)), !
	Quit pRequired
}

/// Compiles the unit conversion component with the build script that came with the package. A jar that is already built is
/// left alone: rebuilding it under a running Java gateway would only disturb the gateway.
ClassMethod BuildUnits(pHome As %String) As %Status
{
	Quit:##class(%File).Exists(##class(Readback.Units.Setup).Jar()) $$$OK
	Set tCode = $ZF(-100, "/SHELL", "bash", pHome_"/java/build.sh")
	Quit:tCode'=0 $System.Status.Error(5001, "java/build.sh exited with code "_tCode)
	Quit $$$OK
}

/// The production names folders and a classpath that are fixed in the image; here they are the package's.
ClassMethod PointProduction(pHome As %String) As %Status
{
	Set tProd = ##class(Ens.Config.Production).%OpenId(..#Production)
	Quit:'$IsObject(tProd) $System.Status.Error(5001, "production not found: "_..#Production)
	Set tPex = "/usr/irissys/dev/java/lib/1.8/intersystems-pex-1.0.0-shaded.jar"
	Set tClasspath = ##class(Readback.Units.Setup).Jar()_":"_##class(Readback.Units.Setup).Ucum()_":"_tPex
	For i = 1:1:tProd.Items.Count() {
		Set tItem = tProd.Items.GetAt(i)
		If tItem.Name = "Readback.Inbound.HL7File" {
			Do ..SetSetting(tItem, "Adapter", "FilePath", ##class(Readback.Config.Paths).Inbox())
			Do ..SetSetting(tItem, "Adapter", "ArchivePath", ##class(Readback.Config.Paths).Archive())
			Do ..SetSetting(tItem, "Adapter", "WorkPath", ##class(Readback.Config.Paths).Work())
		} ElseIf tItem.Name = "Readback.Units" {
			Do ..SetSetting(tItem, "Host", "%gatewayExtraClasspaths", tClasspath)
		}
	}
	Quit tProd.%Save()
}

/// Sets one setting of a production item, adding it when the item does not carry it.
ClassMethod SetSetting(pItem As Ens.Config.Item, pTarget As %String, pName As %String, pValue As %String)
{
	Set tFound = 0
	For j = 1:1:pItem.Settings.Count() {
		Set tSetting = pItem.Settings.GetAt(j)
		If (tSetting.Name = pName) && (tSetting.Target = pTarget) { Set tSetting.Value = pValue, tFound = 1  Quit }
	}
	Quit:tFound
	Set tNew = ##class(Ens.Config.Setting).%New()
	Set tNew.Name = pName, tNew.Target = pTarget, tNew.Value = pValue
	Do pItem.Settings.Insert(tNew)
}

/// Starts the production at the platform's start-up too. The agent that calls a provider is enabled only when a key is set.
ClassMethod Start() As %Status
{
	Set tSC = ##class(Ens.Director).SetAutoStart(..#Production)
	Quit:$System.Status.IsError(tSC) tSC
	Set tLive = (##class(Readback.Config.Mode).Current() = "live")
	If tLive '= ##class(Ens.Director).IsItemEnabled("Readback.Agent") { Set tSC = ##class(Ens.Director).EnableConfigItem("Readback.Agent", tLive) }
	Quit:$System.Status.IsError(tSC) tSC
	If '##class(Ens.Director).IsProductionRunning(..#Production) { Set tSC = ##class(Ens.Director).StartProduction(..#Production) }
	Quit tSC
}

}
