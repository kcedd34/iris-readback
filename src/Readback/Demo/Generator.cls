/// The synthetic HL7 result generator, inside IRIS. The demo builds the message of every submission here, with Embedded Python,
/// from the same Python code that generates the evaluation dataset outside IRIS (src/python/readback/dataset): for the same
/// profile, seed and count the text is identical to the one the command line generator writes.
Class Readback.Demo.Generator
{

/// Profiles the generator knows; the same names as the command line generator.
Parameter Profiles = "samples,evaluation";

/// The largest number of subject cases a generation may ask for.
Parameter MaxCount = 1000;

/// The text of one message (carriage-return segment separators) of the dataset generated for (pProfile, pSeed, pCount): a
/// subject result such as RB2026-00219 or an earlier result of the same patient such as RB2026-00219H1. Returns "" when the
/// arguments are not acceptable or the message is not in that dataset. Nothing of the arguments reaches a file name or a command.
ClassMethod Message(pProfile As %String, pSeed As %Integer, pCount As %Integer, pId As %String) As %String
{
	If '..Acceptable(pProfile, pSeed, pCount, pId) { Quit "" }
	Set tText = ""
	Try { Set tText = ..Generate(pProfile, pSeed, pCount, pId) } Catch ex {
		Set tText = ""
		Do ##class(%SYS.System).WriteToConsoleLog("Readback: the message generator failed: "_$Extract(ex.DisplayString(), 1, 300), 0, 1)
	}
	Quit tText
}

/// True when the arguments are within what a scenario may ask for.
ClassMethod Acceptable(pProfile As %String, pSeed As %Integer, pCount As %Integer, pId As %String) As %Boolean
{
	If (","_..#Profiles_",") '[ (","_$Get(pProfile)_",") { Quit 0 }
	If ($Get(pSeed) '? 1.9N) { Quit 0 }
	If ($Get(pCount) '? 1.4N) { Quit 0 }
	If (pCount < 1) || (pCount > ..#MaxCount) { Quit 0 }
	If ($Get(pId) '? 1"RB"1.9N1"-"5N.1(1"H"1N)) { Quit 0 }
	Quit 1
}

/// Runs the generator of src/python. The Python source folder is put on the module path once per process.
ClassMethod Generate(pProfile As %String, pSeed As %Integer, pCount As %Integer, pId As %String) As %String [ Language = python ]
{
    import sys
    import iris
    folder = iris.cls("Readback.Config.Paths").PythonDir()
    if folder not in sys.path:
        sys.path.insert(0, folder)
    from readback.dataset import generator
    for message_id, text, _ in generator.generate(int(pSeed), int(pCount), pProfile):
        if message_id == pId:
            return text
    return ""
}

}
