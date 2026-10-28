/// The production settings and the code must agree, so the trace can never name a prompt the agent did not get.
Class Readback.Test.DriftTest Extends %UnitTest.TestCase
{

ClassMethod ProductionXml() As %String
{
	Set tX = ##class(%Dictionary.CompiledXData).%OpenId("Readback.Production||ProductionDefinition")
	Quit tX.Data.Read(1000000)
}

Method TestSystemPromptMatchesThePromptClass()
{
	Do $$$AssertTrue(..ProductionXml()[("<Setting Target=""Adapter"" Name=""SystemPrompt"">"_##class(Readback.Triage.Prompt).Text()_"</Setting>"), "the SystemPrompt of Readback.Agent is the prompt class text")
}

Method TestSessionConfigMatchesTheSchemaClass()
{
	Do $$$AssertTrue(..ProductionXml()[("<Setting Target=""Adapter"" Name=""SessionConfigString"">"_##class(Readback.Triage.Schema).SessionConfigJSON()_"</Setting>"), "the SessionConfigString of Readback.Agent is built from the schema class")
}

Method TestAlertChainInTheProduction()
{
	Set tXml = ..ProductionXml()
	Do $$$AssertTrue(tXml[("<Item Name=""Ens.Alert"" Category="""" ClassName=""Readback.Notify.Manager"""), "the platform's alert manager item is the product's subclass")
	Do $$$AssertTrue(tXml[("ClassName=""Ens.Alerting.NotificationManager"""), "the notification manager is the platform's class")
	Do $$$AssertTrue(tXml[("<Setting Target=""Host"" Name=""NotificationTransform"">Readback.Notify.Transform</Setting>"), "the transform maps a level to a person")
	Do $$$AssertTrue(tXml[("<Setting Target=""Host"" Name=""OverdueAlertRule"">Readback.Notify.OverdueRule</Setting>"), "the monitor has its rule")
	Do $$$AssertTrue(tXml[("<Setting Target=""Production"" Name=""AlertNotificationManager"">Readback.Notify.Router</Setting>"), "the production names its notification manager")
	Do $$$AssertTrue(tXml[("ClassName=""Readback.Notify.Operation"""), "the delivery channel is the product's operation")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("Readback.Notify.OverdueRule"), "the rule class exists")
}

Method TestTheKeyIsOnlyAnEnvironmentReference()
{
	Set tXml = ..ProductionXml()
	Do $$$AssertTrue(tXml["@{env:OPENAI_API_KEY}", "the key is referenced from the environment")
	Do $$$AssertTrue(tXml'["sk-", "no key-like text in the production definition")
	Do $$$AssertTrue(tXml'["api_key"":""sk", "no literal key")
}

Method TestSchemaSentToTheProviderIsClosed()
{
	Set tSchema = {}.%FromJSON(##class(Readback.Triage.Schema).SchemaJSON())
	Do $$$AssertEquals(tSchema.additionalProperties, 0, "no extra properties allowed")
	Do $$$AssertEquals(tSchema.required.%Size(), 5, "all five fields are required")
	Do $$$AssertEquals(tSchema.properties.decision.enum.%Size(), 4, "four decisions")
	Do $$$AssertEquals(tSchema.properties.severity.enum.%Size(), 4, "severity 0 to 3")
}

}
