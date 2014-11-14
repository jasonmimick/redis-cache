Include redis.redis

Class redis.InboundAdapter Extends (EnsLib.TCP.InboundAdapter, EnsLib.TCP.TextLineCommon) [ Inheritance = right, ProcedureBlock ]
{

// Include redis.redis

Parameter SERVICEINPUTCLASS = "redis.Request";

Parameter SERVICEOUTPUTCLASS = "redis.Response";

/* override (empty) superclass initial Terminators value */
Property Terminators As %String [ InitialExpression = {$C(13,10)} ];

Method OnConnected() As %Status
{
	Set redisRequest=$$$NULLOREF
	Set tQuitErr=1  Do {
		//Set tSC=..ReadLine(.tInStr,..CallInterval,1)
		set ..Socket.LineTerminator=$C(13,10)
		Set tSC = ##class(redis.Request).readFromStream(..Socket,.redisRequest)
		set redisRequest.Client = $piece(..IOAddr,"-",2)
		If $$$ISERR(tSC) {
			If ..IsReadError(tSC) {
				Set tSC=$$$ERROR($$$EnsErrInConnectionLost,"TCP Read Line",..IOAddr,$$$StatusDisplayString(tSC))
				set tSCt=..CleanUpMonitors()
				if ($$$ISERR(tSCt)) { /*$$$LOGWARNING(tSCt)*/ }
				Set tQuitErr=0  Do ..Disconnect()
				If ""=redisRequest Set tTxt=$$$StatusText(tSC), tSC=$$$OK  If ..StayConnected<0 { /*$$$LOGWARNING(tTxt)*/ } ElseIf ..%logConnections { $$$LOGINFO(tTxt) } Else { $$$sysTRACE(tTxt) } ; change error to info if lost connection with no data and trying to stay connected
			} ElseIf $$$StatusEquals(tSC,$$$EnsErrTCPTerminatedReadTimeoutExpired) {
				If ""=redisRequest { Set tSC=$$$OK } ; no error if timed out with no data
				Else { Set tQuitErr=0 }
			}
			Quit
		}
		$$$ANEWINIOLOGENTRY($$$OK,"redis.Inbound req :"_..IOAddr,redisRequest.toString())
		$$$TRACE("request="_redisRequest.toString())
		// If someone is monitoring, signal them
		// TODO: Refactor into CommandProcessor
		if ( $get(^redis.monitor,0)=1 ) {
			$$$TRACE("^redis.montior is 1")
			set rlist=$system.Event.List()
			for i=1:1:$listlength(rlist) {
				if ($list(rlist,i)["redis.monitor") {
					set msg=redisRequest.toString()
					$$$TRACE("sending to '"_$list(rlist,i)_"' msg="_msg)
					do $system.Event.Signal($list(rlist,i),msg)
				}
			}
		}
		// Process the request
		Set tSC=..BusinessHost.ProcessInput(.redisRequest, .redisResponse)  Quit:$$$ISERR(tSC)
		
		If $D(redisResponse) {
			If $IsObject(redisResponse) {
				$$$ASSERT(redisResponse.%Extends("redis.Response"))
				if ( '$isobject(redisResponse.Request) ) {
					set redisResponse.Request=redisRequest
				}
				//Set tStringOut=tStringOut.StringValue
			}
		} Else { Set redisResponse=##class(redis.Response).Error("UNKNOWN") }
		If $$$ISERR(tSC) {
			$$$ACLOSEIOLOGENTRY(tSC,"after TCP TextLine ProcessInput error on :"_..IOAddr,redisRequest.toString())
			Quit
		}
		//If ""'=tStringOut {
		If $isobject(redisResponse) {
			if ( redisResponse.Request.Command = "QUIT" ) {
				Do ..Disconnect()
				Goto QuitOK
			}
			;#$$$sysTRACE("Returning Output String '"_tStringOut_"'")
			//Set tSC=..WriteLine(tStringOut,1)
			Set tSC = redisResponse.writeToStream(..Socket)
			If $$$ISERR(tSC) {
				If ..IsWriteError(tSC) {
					Set tSC=$$$ERROR($$$EnsErrInConnectionLost,"TCP Write Line",..IOAddr,$$$StatusDisplayString(tSC))
					Set tQuitErr=0  Do ..Disconnect()
				}
				$$$ACLOSEIOLOGENTRY(tSC,"after TCP WriteLine error on :"_..IOAddr,"redisReponse.toString()")
				Quit
			}
			$$$ACLOSEIOLOGENTRY(tSC,"after TCP WriteLine on :"_..IOAddr,"redisReponse.toString()")
		} Else {
			$$$ACLOSEIOLOGENTRY(tSC,"after TCP ProcessInput on :"_..IOAddr,"")
		}
	} While 0
	#; Returning error status would cause this listener job to terminate
	If $$$ISERR(tSC) {
		#; Never quit the listener, but drop the connection on unrecognized error
		If tQuitErr&&..Connected&&..StayConnected { $$$LOGERROR("Disconnecting due to "_$$$StatusDisplayString(tSC)) Set tSC=$$$OK  Do ..Disconnect() }
		If $$$ISERR(tSC) $$$LOGSTATUS(tSC)
	}
QuitOK
	Quit $$$OK
}

Method OnTearDown() As %Status
{
	
	$$$TRACE("OnTearDown")
	return ##super()
	//return $$$OK
}

Method CleanUpMonitors() As %Status
{
	$$$TRACE("CleanUpMonitors")
	
	set client = $piece(..IOAddr,"-",2)
	if ( client = "" ) {
		$$$TRACE("CleanUpMonitor client="""" IOAddr="_..IOAddr)
		quit $$$OK
	}
	// if any monitors are listening on this client connection
	// send them the UNSUBSCRIBE message to stop listening
	set channel=$order(^redis.channels(""))
	while ( channel'="" ) {
		if ( $data( ^redis.channels(channel,client) ) ) {
			set pipe="^redis.channels("""_channel_""","""_client_""")"
			set ret=$system.Event.Signal(pipe,"UNSUBSCRIBE")
			$$$TRACE("OnTearDown sent UNSUBSCRIBE to "_pipe)
		}
		set channel=$order(^redis.channels(channel))
	}
	if ( $data( $$$clients(client,"monitor")) )  {
		set pipe=$$$clients(client,"monitor")
		set ret=$system.Event.Delete(pipe)
		$$$TRACE("CleanUpMonitors deleted event="_pipe)
	}
	return $$$OK
}

}

