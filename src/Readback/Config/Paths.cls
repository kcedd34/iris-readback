/// Where the product's files live. In its own image they are under /opt/readback and /data; when the product is
/// installed as a package, the install step records a root under the instance and these methods follow it.
Class Readback.Config.Paths
{

Parameter DefaultRoot = "/opt/readback";

/// The root of the product's files: the one the install step recorded, or the image's.
ClassMethod Root() As %String
{
	Set tHome = $Get(^Readback("home"))
	Quit $Select(tHome '= "": tHome, 1: ..#DefaultRoot)
}

ClassMethod Installed() As %Boolean
{
	Quit $Get(^Readback("home")) '= ""
}

/// Configuration, policy and replay recordings.
ClassMethod Data() As %String
{
	Quit ..Root()_"/data"
}

/// The synthetic messages the demo scenarios send.
ClassMethod Samples() As %String
{
	Quit ..Root()_"/samples"
}

/// The Python sources of the synthetic message generator, which Readback.Demo.Generator imports inside IRIS: in the image they
/// are part of the source tree, in an installed package they are copied beside the other files.
ClassMethod PythonDir() As %String
{
	Quit $Select(..Installed(): ..Root()_"/python", 1: ..Root()_"/src/python")
}

/// The unit conversion component's sources, jar and libraries.
ClassMethod JavaDir() As %String
{
	Quit ..Root()_"/java"
}

/// Intake, archive and work folders of the file service and of the demo submissions.
ClassMethod Inbox() As %String
{
	Quit $Select(..Installed(): ..Root()_"/in", 1: "/data/in")
}

ClassMethod Archive() As %String
{
	Quit $Select(..Installed(): ..Root()_"/archive", 1: "/data/archive")
}

ClassMethod Work() As %String
{
	Quit $Select(..Installed(): ..Root()_"/work", 1: "/data/work")
}

}
