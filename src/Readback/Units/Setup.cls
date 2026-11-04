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

/// Seconds to wait for the Java gateway to accept a connection, and the pause between attempts.
Parameter GatewayWait = 90;

Parameter GatewayPause = 3;

/// How many times the registration is tried (it starts the Java gateway, which can be slow to listen on a loaded machine).
Parameter RegisterAttempts = 4;

Parameter GatewayName = "%Java Server";

/// True when the Java gateway at the address and port answers over its own protocol within pTimeout seconds. A bare TCP connection is not
/// the test: connecting and closing without speaking the protocol can leave the gateway unable to take the next real connection.
ClassMethod Accepts(pAddress As %String, pPort As %Integer, pTimeout As %Integer = 5) As %Boolean
{
	Set tOk = 0
	Try {
		Set tConnection = ##class(%Net.Remote.Gateway).%New()
		Set tSC = tConnection.%Connect(pAddress, pPort, $Namespace, pTimeout)
		If $System.Status.IsOK(tSC) { Set tOk = ''tConnection.isAlive() }
		Do tConnection.%Disconnect()
	} Catch ex { Set tOk = 0 }
	Quit tOk
}

/// Calls pProbe (a class method of pClass, this class by default, that returns 1 when the thing is ready) until it does or pSeconds have passed. Returns the number of attempts made in pAttempts and an error status naming what was waited
/// for when the time ran out.
ClassMethod WaitUntil(pProbe As %String, pSeconds As %Integer, pPause As %Integer, pWhat As %String, Output pAttempts As %Integer = 0, pClass As %String = {$ClassName()}) As %Status
{
	Set tEnd = $ZHorolog + pSeconds, pAttempts = 0
	For {
		Set pAttempts = pAttempts + 1
		Set tReady = 0
		Try { Set tReady = $ClassMethod(pClass, pProbe) } Catch ex { Set tReady = 0 }
		If tReady { Quit }
		If ($ZHorolog + pPause) > tEnd { Quit }
		Hang pPause
	}
	If tReady { Quit $$$OK }
	Quit $System.Status.Error(5001, pWhat_" did not become ready within "_pSeconds_" seconds ("_pAttempts_" attempts)")
}

/// The probe of the Java gateway: it accepts a connection, and when it does not, it is started (a gateway that is down is not a gateway that
/// will come up by itself). Used by WaitUntil.
ClassMethod GatewayReady() As %Boolean
{
	Set tSC = ##class(%Net.Remote.Service).OpenGateway(..#GatewayName, .tGateway)
	If $System.Status.IsError(tSC) { Quit 0 }
	If ..Accepts(tGateway.BindToIPAddress, tGateway.Port) { Quit 1 }
	Do ##class(%Net.Remote.Service).StartGateway(..#GatewayName, 0, .tOutput, 1)
	Quit ..Accepts(tGateway.BindToIPAddress, tGateway.Port, 5)
}

/// Waits for the Java gateway to accept a connection, with new attempts, and fails with a message that says what was not reachable.
ClassMethod WaitForGateway(pSeconds As %Integer = {..#GatewayWait}) As %Status
{
	Set tSC = ..WaitUntil("GatewayReady", pSeconds, ..#GatewayPause, "the Java gateway ("_..#GatewayName_")", .tAttempts)
	If $System.Status.IsOK(tSC) && (tAttempts > 1) { Write "Readback: the Java gateway accepted a connection at attempt ", tAttempts, !, ! }
	Quit tSC
}

/// Registers the Java component (the registration starts the Java gateway with the component's class path, so it is not started beforehand: a
/// gateway started first is restarted by the registration and the two collide), tries again when it fails, and then waits until the gateway
/// accepts a connection. Returns an error that says which of the two did not happen when the attempts run out.
ClassMethod EnsureComponent() As %Status
{
	If '##class(%File).Exists(..Jar()) { Quit $System.Status.Error(5001, "unit conversion component not built: "_..Jar()_" is missing") }
	Set tStamp = ##class(%File).GetFileDateModified(..Jar())
	If '(##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass) && ($Get(^Readback("unitsJar")) = tStamp)) {
		Set tPath = ..Jar()_":"_..Ucum()_":"_..#PexJar
		Set tSC = $$$OK
		For tTry = 1:1:..#RegisterAttempts {
			Set tSC = ##class(EnsLib.PEX.Utils).RegisterComponent("com.readback.units.UnitsOperation", ..#GatewayName, tPath, 1, ..#ProxyClass, 1)
			If $System.Status.IsOK(tSC) && '##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass) {
				Set tSC = $System.Status.Error(5001, "the component was registered but its proxy class "_..#ProxyClass_" does not exist")
			}
			If $System.Status.IsOK(tSC) { Quit }
			Write "Readback: registering the unit conversion component failed at attempt ", tTry, " of ", ..#RegisterAttempts, ": ", $System.Status.GetErrorText(tSC), !
			If tTry < ..#RegisterAttempts { Hang ..#GatewayPause * tTry }
		}
		If $System.Status.IsError(tSC) { Quit $System.Status.Error(5001, "the unit conversion component could not be registered after "_..#RegisterAttempts_" attempts: "_$System.Status.GetErrorText(tSC)) }
		Set ^Readback("unitsJar") = tStamp
	}
	Quit ..WaitForGateway()
}

/// True when the proxy class of the component exists, for the status endpoint.
ClassMethod IsRegistered() As %Boolean
{
	Quit ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProxyClass)
}

}
