Include redis.redis

Class redis.Monitor Extends %RegisteredObject
{

ClassMethod Tail(request As redis.Request) As %Status
{
	set i=$G(^Ens.Util.LogD,0)
	set i=i-100,tail=1
	while (tail) {
		if ( '$data(^Ens.Util.LogD(i)) ) {
			hang 1
			read x:.2	// chance to quit nicely
			if (x'="") { quit }
			continue
		}
		set log=^Ens.Util.LogD(i)
		write i,":",$list(log,8)," ",$list(log,7),!
		set i=i+1
	}
	write "bye.",!
}

ClassMethod Subscribe(request As redis.Request) As %Status
{
	// wait on all my channels for messages
	// when you get one, send it to the request.Stream
	set channels=$$$clients(request.Client,"channels")
	$$$TRACE("Subscribe channels="_$listtostring(channels))
	set channelPipes=""
	for i=1:1:$ll(channels) {
		set channel=$list(channels,i)
		set in=request.getChannelEvent(channel)	
		if ( '$system.Event.Defined(in) ) {
			$$$TRACE("Subscribe create event:"_in)
			set ret=$system.Event.Create(in)
		}
		set $list(channelPipes,$ll(channelPipes)+1)=in
		// any stored message on this channel
		set numStoredMessages=$get( $$$channelmessages(channel), 0 )
		for j=1:1:numStoredMessages {
			set m=$$$channelmessages(channel,j)
			set r=$$$rBULK($listbuild("message",channel,m))
			set sc=r.writeToStream(request.Stream)
		}
	}
	$$$TRACE("Subscribe channelPipes="_$listtostring(channelPipes))
	set subscribed=1
	while ( subscribed ) {
		//set timeout=$$$PUBSUBPOLLINTERAL
		set timeout=2	// check pipes every second
		set subscribed=$listlength(channelPipes)
		$$$TRACE("Subscribe start pipe loop subscribed="_subscribed_" channelPipes="_$listtostring(channelPipes))
		for i=1:1:$ll(channelPipes) {
			quit:('subscribed)
			continue:('$listdata(channelPipes,i))
			set pipe=$list(channelPipes,i)
			$$$TRACE("Pub/Sub waiting on pipe="_pipe)
			set msgl=$system.Event.WaitMsg(pipe,timeout)
			set connected=$system.INetInfo.Connected()
			$$$TRACE("Pub/Sub pipe="_pipe_" msg="_$listtostring(msgl)_" connected="_connected)
			if ( 'connected ) {
				set subscribed=0
				for jj=1:1:$ll(channelPipes) {
					set cp=$list(channelPipes,jj)
					set ch=$list(channels,jj)
					set r=$system.Event.Delete(cp)
					$$$TRACE("Deleted "_cp_" ret="_ret)
					kill $$$channels(ch,request.Client)	
					set x=$increment($$$channels(ch),-1)

				}
				continue
			}
			if ( $list(msgl,1) = 1 ) {
				set msg=$list(msgl,2)
				if ( msg="UNSUBSCRIBE" ) {
					set $list(channelPipes,i,i+1)=""
					set subscribed=$ll(channelPipes)
					set r=$system.Event.Delete(pipe)
					kill $$$channels(pipe,request.Client)
					set x=$i($$$channels(pipe),-1)
					continue // pipe loop
				}	
				// send message
				set r=$$$rBULK($listbuild("message",$list(channels,i),msg))
				set sc=r.writeToStream(request.Stream)
			}
			if ( $list(msgl,1) = -1 ) {
				//set subscribed=0
				$$$TRACE("Subscribe WaitMsg return -1, pipe deleted="_pipe)
				set $list(channelPipes,i,i+1)=""
				set subscribed=$listlength(channelPipes)
				kill $$$channels(pipe,request.Client)
				set x=$i($$$channels(pipe),-1)
				continue // pipe loop
			}
		}
		// otherwise, WaitMg timedout - 
		// check wire for any new requests.
		// - the client won't send command on same socket
		// - they should use CLIENT SETNAME
		// - make another connection, set to same name
		// - and issue unsubscribe from there!
		/*
		*/
	}
	return $$$rOK
}

ClassMethod Unsubscribe(request As redis.Request, channel As %String) As %Status
{
	set in=request.getChannelEvent(channel) //"^redis.channels("""_channel_""")"
	if ( '$system.Event.Defined(in) ) {
		$$$TRACE("Unsubscribe but channel event does not exist!")
		return $$$OK
	}
	set ret=$system.Event.Signal(in,"UNSUBSCRIBE")
	$$$TRACE("Unsubscribe sent 'UNSUBSCRIBE' to "_in)
	return $$$OK
}

ClassMethod Publish(request As redis.Request, channel As %String, message As %String) As %Integer
{
	$$$TRACE("Publish channel="_channel_" message="_message)

	// save message for later subscriber delivery
	set i = $i($$$channelmessages(channel))
	set $$$channelmessages(channel,i)=message
	set clientCount=0	
	set client=$order($$$channels(channel,""))
	while ( client'="" ) {
		set event="^redis.channels("""_channel_""","""_client_""")"
		if ( '$system.Event.Defined(event) ) {
			$$$TRACE("Publish creating "_event)
			set ret=$system.Event.Create(event)
		}
		set ret=$system.Event.Signal(event,message)
		$$$TRACE("Publish sent message="_message_" to event="_event_" ret="_ret)
		set x=$increment(clientCount)
		set client=$order($$$channels(channel,client))
	}
	return clientCount
}

ClassMethod Start(request As redis.Request) As %Status
{
	set resource="^redis.monitor("""_request.Client_""")"
	set $$$clients(request.Client,"monitor")=resource
	set stream = request.Stream
	$$$TRACE("redis.Monitor.Start resource="_resource_" stream.IsOpen="_stream.IsOpen)
	set ^redis.monitor=1,status=$$$OK
	set created=$system.Event.Create(resource)
	$$$TRACE(resource_" created="_created)
	set timeout=2
	while ( stream.IsOpen ) {
		set connected=$system.INetInfo.Connected()
		if ( 'connected ) {
			$$$TRACE("redis.Monitor.Start loop - connected="_connected)
			quit
		}
		set msgl=$system.Event.WaitMsg(resource,timeout)
		set msg=$list(msgl,2),code=$list(msgl,1)
		if ( code=0 ) { 	//timedout
			continue
		}
		if ( code=-1 ) { 	// event resource deleted
			$$$TRACE("redis.Moitor.Start loop resource deleted code="_code)
			quit
		}
		$$$TRACE(resource_" Msg="_msg)
		if ( $list(msgl,1)'=1 ) { // not a normal wakeup event
			$$$TRACE(resource_" got timeout or delete msgl="_$listtostring(msgl))
			quit
		}
		if ( $zconvert(msg,"l")["monitor.stop" ) {
			$$$TRACE(resource_" got Monitor.Stop")
			break
		}
		if ( stream.IsOpen ) {
			//do stream.WriteLine(msg,1,.status)
			set response=$$$rBULK(msg)
			set status=response.writeToStream(.stream)
			quit:$$$ISERR(status)
		}
	}
	set deleted=$system.Event.Delete(resource)
	$$$TRACE(resource_" delete="_deleted)
	// if no other monitors running, turn off global switch
	set found=0,pmonitors=$system.Event.List()
	for i=1:1:$listlength(pmonitors) {
		if ( $list(pmonitors,i)["redis.monitor" ) {
			set found=1
		}
	}
	// TODO LOCK!
	$$$TRACE(resource_"found="_found)
	set:'found ^redis.monitor=0
	return status
}

ClassMethod ForceAllMonitorsDown() As %Status
{
	set events=$system.Event.List()
	for i=1:1:$listlength(events) {
		set mon=$list(events,i)
		if ( mon["redis.monitor" ) {
			set sent=$system.Event.Signal(mon,"monitor.stop")
			write "Sent 'Monitor.Stop' to ",mon," sent=",sent,!
			set monitors(mon)=""
		}
		if ( mon["redis.channels" ) {
			set sent=$system.Event.Signal(mon,"UNSUBSCRIBE")
			write "Sent 'UNSUBSCRIBE' to "_mon,!
			set monitors(mon)=""
		}
	}
	if ( '$data(monitors) ) {
		write " ForceAllMonitorsDown Done."
		quit
	}
	set waitSeconds = 5
	write "Waiting "_waitSeconds_" for monitors to close"
	for i=1:1:5 { write "." hang 1 }
	write !
	set mon=$order(monitors(""))
	while ( mon'="" ) {
		if ( $system.Event.Defined(mon) ) {
			write mon," exists!, attempting to delete result="
			set dr=$system.Event.Delete(mon)
			write dr,!
		}
		set mon=$order(monitors(mon))
	}
}

}

