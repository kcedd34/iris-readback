/// Run mode: live when a provider key is configured, replay otherwise.
/// The key value is never returned, logged or stored.
Class Readback.Config.Mode
{

/// "live" only when OPENAI_API_KEY, trimmed, is non-empty; otherwise "replay".
ClassMethod Current() As %String
{
	Set tKey = $ZStrip(..KeyText(), "<>W")
	Quit $Select(tKey'="":"live", 1:"replay")
}

/// The configured key text. Only this method reads the key, and nothing outside it keeps the value.
/// A process-private global lets tests set the key without touching the environment of the instance.
ClassMethod KeyText() [ Private ]
{
	Quit:$Data(^||ReadbackTestKey) ^||ReadbackTestKey
	Quit $System.Util.GetEnviron("OPENAI_API_KEY")
}

}
