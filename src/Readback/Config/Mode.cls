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

/// Removes credentials from an error text, whatever its source (the real provider, the mock, the platform).
/// Three layers: the configured key in every form it can take in a message (as is, URL-encoded, escaped for
/// JSON), then any key-shaped token (a provider may echo the key masked or cut, so the exact value is not enough),
/// then the value that follows a credential word or an Authorization header. Text without a credential is unchanged.
ClassMethod Redact(pText As %String) As %String
{
	Set tText = pText
	Set tKey = $ZStrip(..KeyText(), "<>WC")
	If $Length(tKey) >= 4 {
		Set tForms = $ListBuild(tKey, $ZConvert(tKey, "O", "URL"), $Replace($Replace(tKey, "\", "\\"), """", "\"""), $System.Encryption.Base64Encode(tKey))
		Set tPtr = 0
		While $ListNext(tForms, tPtr, tForm) { If $Length(tForm) >= 4 { Set tText = $Replace(tText, tForm, "[key redacted]") } }
	}
	Set tPatterns = $ListBuild("(?i)\bsk-[A-Za-z0-9_*.\-]{3,}", "(?i)\bBearer\s+[^\s,;'""]+", "(?i)\bBasic\s+[A-Za-z0-9+/=]{8,}")
	Set tPtr = 0
	While $ListNext(tPatterns, tPtr, tPattern) { Set tText = ##class(%Regex.Matcher).%New(tPattern, tText).ReplaceAll("[key redacted]") }
	// "API key provided: <value>", "authorization=<value>", "password: <value>": the word stays, the value goes.
	Set tText = ##class(%Regex.Matcher).%New("(?i)\b(api[ _-]?key|authorization|auth[ _-]?token|access[ _-]?token|secret|password|credential)s?(\s+provided)?\s*[:=]\s*(?!\[key redacted\])[""']?[^\s,;'""]+", tText).ReplaceAll("$1: [key redacted]")
	Quit tText
}

/// The platform's own agent operation writes the provider's error text to the event log, and the engine keeps it
/// in the message header, before the product sees it: a provider that echoes the credential puts it in both. The
/// product cannot stop those writes; it removes the credential from the rows of the item right after a failed call
/// (the last two minutes, so a late write is covered). StatusValue is dropped because it is a packed copy of the
/// same text. Never raises; a failure is reported to the console log without the text.
ClassMethod ScrubEventLog(pConfigName As %String = "Readback.Agent")
{
	Try {
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Text FROM Ens_Util.Log WHERE ConfigName = ? AND TimeLogged >= DATEADD('second', -120, GETUTCDATE())", pConfigName)
		While tRS.%Next() {
			Set tId = tRS.%Get("ID"), tText = tRS.%Get("Text"), tClean = ..Redact(tText)
			If tClean '= tText { &sql(UPDATE Ens_Util.Log SET Text = :tClean, StatusValue = NULL WHERE ID = :tId) }
		}
		Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ErrorStatus FROM Ens.MessageHeader WHERE (TargetConfigName = ? OR SourceConfigName = ?) AND ErrorStatus IS NOT NULL AND TimeCreated >= DATEADD('second', -120, GETUTCDATE())", pConfigName, pConfigName)
		While tRS.%Next() {
			Set tId = tRS.%Get("ID"), tStatus = tRS.%Get("ErrorStatus"), tText = $System.Status.GetErrorText(tStatus), tClean = ..Redact(tText)
			If tClean '= tText { Set tNew = $System.Status.Error(5001, tClean)  &sql(UPDATE Ens.MessageHeader SET ErrorStatus = :tNew WHERE ID = :tId) }
		}
	} Catch ex {
		Do ##class(%SYS.System).WriteToConsoleLog("Readback: event log scrub failed, code "_ex.Code, 0, 1)
	}
}

/// The configured key text. Only this method reads the key, and nothing outside it keeps the value.
/// A process-private global lets tests set the key without touching the environment of the instance.
ClassMethod KeyText() [ Private ]
{
	Quit:$Data(^||ReadbackTestKey) ^||ReadbackTestKey
	Quit $System.Util.GetEnviron("OPENAI_API_KEY")
}

}
