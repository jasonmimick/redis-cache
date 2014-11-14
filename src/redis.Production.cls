Include redis.redis

Class redis.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="redis.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description></Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="redis.Service" Category="" ClassName="redis.Service" PoolSize="50" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="Port">6379</Setting>
    <Setting Target="Adapter" Name="QSize">1000</Setting>
    <Setting Target="Host" Name="ArchiveIO">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="StayConnected">-1</Setting>
  </Item>
</Production>
}

/// Override this in your Production class to do setup before the Production starts
ClassMethod OnStart(pTimeStarted As %String) As %Status
{
	
	for glo="^redis.clients","^redis.channels","^redis.channels.messages" {
		$$$TRACE("redis.Production OnStart - clearing "_glo)
		kill @glo
	}
	Quit $$$OK
}

/// Override this in your Production class to do cleanup after the Production stops
ClassMethod OnStop(pTimeStarted As %String, pForced As %Boolean)
{
	
	$$$TRACE("OnStop")
	do ##class(redis.Monitor).ForceAllMonitorsDown()
	Quit
}

}

