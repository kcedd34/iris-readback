/// The rule the platform's monitor evaluates for an overdue alert. It only says that a notification is wanted; the next level
/// and the next time are set on the context by Readback.Notify.Monitor. The monitor skips the context when no rule is set.
Class Readback.Notify.OverdueRule Extends Ens.Rule.Definition
{

Parameter RULECONTEXT = "Ens.Alerting.Context.OverdueAlert";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="Ens.Alerting.Context.OverdueAlert" production="">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="notify">
<when condition="1">
<return>1</return>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
