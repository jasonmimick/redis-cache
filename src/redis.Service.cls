Class redis.Service Extends Ens.BusinessService
{

Parameter ADAPTER = "redis.InboundAdapter";

Property CommandProcessor As redis.CommandProcessor;

Method OnInit() As %Status
{
	Set $this.CommandProcessor=##class(redis.CommandProcessor).%New()
	$$$TRACE("$this.CommandProcessor="_$this.CommandProcessor)
	Quit $$$OK
}

Method OnProcessInput(redisRequest As redis.Request, Output redisResponse As redis.Response) As %Status
{

	Set redisResponse=$$$NULLOREF
	$$$TRACE("OnProcessInput---"_redisRequest.toString())		
	set status=$this.CommandProcessor.Process(redisRequest,.redisResponse)
	
	/*
	set command = redisRequest.Command
	if ( command="PING" ) {
		set redisResponse=##class(redis.Response).OK("PONG",.redisRequest)
		
	} else {
		set redisResponse=##class(redis.Response).Error("unknown command '"_command_"'",.redisRequest)
	}
	*/
	$$$TRACE("OnProcessInput response="_redisResponse.toString())
	Quit status
}

}

