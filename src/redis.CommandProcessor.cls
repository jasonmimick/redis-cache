Include redis.redis

/// Private methods for each command this redis server implements.
/// Only entry is through Process() which catches exceptions and returns
/// %Status'
Class redis.CommandProcessor Extends %RegisteredObject
{

/// Cache of namespaces we're already checked
Property CheckedNamespaces As %String [ MultiDimensional, Private ];

Parameter KeyWildcard As %String = "*";

ClassMethod document()
{
	#dim method as %Dictionary.MethodDefinition
	set cdef=##class(%Dictionary.ClassDefinition).%OpenId(..%ClassName(1))
	for i=1:1:cdef.Methods.Count() {
		set method = cdef.Methods.GetAt(i)
		set name=method.Name
		if ( name?.U ) {	// all uppercase name => redis command
			set commands(name)="",x=$increment(commandCount)
		}
		if ( name?.U1"and".U ) {
			set commands(name)="",x=$increment(commandCount)
		}
	}
	set name=$order(commands(""))
	while ( name'="" ) { write name,! set name=$order(commands(name)) }
	write "# command supported:",commandCount,!
}

Method %OnNew(type) As %Status
{
	Set $this.CheckedNamespaces($namespace)=""
	return $$$OK
}

//'
Method Process(ByRef request As redis.Request, Output response As redis.Response) As %Status
{
	#dim exception as %Exception.AbstractException
	try {
		set $$$clients(request.Client,"addr")=request.Client
		if ( $data( $$$clients(request.Client,"db") ) ) {
			set ns=$$$clients(request.Client,"db")
			if ( '$data(..CheckedNamespaces(ns) ) ) {
				set sc=##class(redis.SystemUtilities).EnsureNamespace( $$$clients("db") )
				if $$$ISERR(sc) $$$ThrowStatus(sc) 
				set $this.CheckedNamespaces(ns)=""
			}
		} else { 			
			set $$$clients(request.Client,"db")=$namespace
		}
		set command = request.Command
		$$$TRACE("command="_command)
		set response=$method($this,command,request)
		return $$$OK
	} catch (exception) {
		$$$TRACE(exception.DisplayString())
		set response=$$$rERROR(exception.DisplayString())
		// We eat and return exceptions from here down
		// as they are "application" issues which we need
		// to send back to the client
		return $$$OK //exception.AsStatus()
	}
}

Method QUIT(request As redis.Request) As redis.Response [ Private ]
{
	$$$TRACE("QUIT - request.Client = "_request.Client)
	return $$$rOKMSG("BYE")
}

Method MONITOR(request As redis.Request) As redis.Response [ Private ]
{
	// special debugging request to track requests
	$$$TRACE("MONITOR - request.Client="_request.Client)
	set sc=##class(redis.Monitor).Start(.request)
	$$$TRACE("redis.Monitor.Start returned sc="_$system.Status.GetErrorText(sc))
	return $$$rOK
}


Method SUBSCRIBE(request As redis.Request) As redis.Response [ Private ]
{
	if ( $data( $$$clients(request.Client,"channels") ) ) {
		set myChannels = $$$clients(request.Client,"channels")
	} else {
		set myChannels = ""
	}
	$$$TRACE("SUBSCRIBE channels="_$listtostring(request.Arguments)_" current ="_$listtostring(myChannels))
	set numChannels=$listlength(request.Arguments)
	for i=1:1:numChannels { 	// for each channel
		set channel=$list(request.Arguments,i)
		// does this client already subscribe?
		if ( '$listfind(myChannels,channel) ) {
			set $list(myChannels,$ll(myChannels)+1)=channel
		}
		set x=$increment($$$channels(channel))
		set $$$channels(channel,request.Client)=x	
		set $$$clients(request.Client,"channels")=myChannels
		set result=$listbuild("subscribe",channel,$listlength(myChannels))
		set response=$$$rBULK(result)
		set sc=response.writeToStream(request.Stream)	
	}
	set response=##class(redis.Monitor).Subscribe(request)
	return response
}

Method UNSUBSCRIBE(request As redis.Request) As redis.Response [ Private ]
{
	set name=$get($$$clients(request.Client,"name"))
	if ( name="" ) {
		return ..unsubscribeClient(request.Client,request)
	}
	// may need to send unsubscribe
	// to other clients with same name
	set client=$order($$$clients.index("name",name,""))
	set clients=""
	while ( client'="" ) {
		set $list(clients,$ll(clients)+1)=client
		set client=$order($$$clients.index("name",name,client))
	}
	for i=1:1:$ll(clients) {
		set client=$list(clients,i)
		set response=unsubscribeClient(client,request)
		do:(i<$ll(clients)) responses.writeToStream(request.Stream)
	}
	return response
}

Method unsubscribeClient(client As %String, request As redis.Request) As redis.Response [ Private ]
{
	if ( '$data( $$$clients(client,"channels") ) ) {
		// ain't got no subscriptions!
		return $$$rERROR("No subscriptions found!")
	}
	if ( $listlength(request.Arguments) = 0 ) { // unsubscribe from all
		set channels = $$$clients(client,"channels")
	} else {
		set channels = request.Arguments
	}
	$$$TRACE("UNSUBSCRIBE from "_$listtostring(channels))
	set numChannels=$listlength(channels),response=$$$rOK
	for i=1:1:numChannels { 	// for each channel
		set channel=$list(channels,i)
		// does this client already subscribe?
		set cp=$listfind( $$$clients(clients,"channels"),channel )
		if ( cp=0 ) {
			// not subscribed, continue
			continue
		}
		// remove the channel
		set $list($$$clients(client,"channels"),cp,cp+1)=""
		kill $$$channels(channel,client)	
		set x=$increment($$$channels(channel),-1)
		set numChannels=$listlength($$$clients(client,"channels"))
		set result=$listbuild("unsubscribe",channel,numChannels)
		set response=$$$rBULK(result)
		// save last response to return
		do ##class(redis.Monitor).Unsubscribe(request,channel)
		set:(i<numChannels) sc=response.writeToStream(request.Stream)	
	}
	return response
}

Method PUBLISH(request As redis.Request) As redis.Response [ Private ]
{
	if ( $listlength(request.Arguments)'= 2 ) {
		return $$$rERROR("PUBLISH invalid args "_$listtostring(request.Arguments))
	}
	set channel=$list(request.Arguments,1)
	set message=$list(request.Arguments,2)
	$$$TRACE("PUBLISH channel="_channel_" message="_message)
	set i=##class(redis.Monitor).Publish(request,channel,message)
	return $$$rINT(i)
}

Method PING(request As redis.Request) As redis.Response [ Private ]
{
    $$$TRACE("PING client="_request.Client)
    return $$$rOKMSG("PONG")
}

Method CLIENT(request As redis.Request) As redis.Response [ Private ]
{
	set command = $zconvert($list(request.Arguments,1),"U")
	$$$TRACE("CLIENT command="_command)
	if ( "KILL,LIST,SETNAME,GETNAME"'[command ) {
		return $$$rERROR("UNKNOWN CLIENT COMMAND '"_command_"'")
	}
	set subCommand="CLIENTand"_command
	return $method($this,subCommand,request)
}

Method CLIENTandLIST(request As redis.Request) As redis.Response [ Private ]
{
	set fields=$lb("addr","age","name","db")
	set c=$order($$$clients("")),tr="",cc=0
	while ( c'="" ) {
		set l=""
		for i=1:1:$ll(fields) {
			set f = $list(fields,i)
			set l = l_f_":"_$get($$$clients(c,f),"???")
			set:i<$ll(fields) l=l_" "
		}

	// set tr=tr_"$"_$length(l)_$$$CRLF

	// set tr=tr_l_$$$CRLF,cc=cc+1
	set tr=tr_l_$C(10),cc=cc+1
		set c=$order($$$clients(c))
		//set:(c'="") tr=tr_$C(10)
	}
	//set result="*1"_$$$CRLF_"$"_$l(tr)_$$$CRLF_tr_$$$CRLF
	return $$$rBULK(tr)
}

Method CLIENTandKILL(request As redis.Request) As redis.Response [ Private ]
{
	set target=$list(request.Arguments,2)
	if ( '$data($$$clients(target) ) ) {
		return $$$rERROR("CLIENT NOT FOUND")
	}
	if ( $data($$$clients(target,"busy"))) {
		return $$$rERROR("CLIENT BUSY")
	}

	// TODO - use LOCKs on ^redis.clients here
	$$$TRACE("CLIENT KILL *** Locks not implemented ***")
	set name=$get($$$clients(target,"name"))
	kill $$$clients(target)
	kill:(name'="") $$$clients.index("name",name,target)
	return $$$rOK
}

Method CLIENTandSETNAME(request As redis.Request) As redis.Response [ Private ]
{
	set name=$list(request.Arguments,2)
	set $$$clients(request.Client,"name")=name
	set $$$clients.index("name",name,request.Client)=""
	return $$$rOK
}

Method CLIENTandGETNAME(request As redis.Request) As redis.Response [ Private ]
{
	$$$TRACE("cCLIENTcGETNAME request.Client="_request.Client)
	if ( '$data($$$clients(request.Client,"name")) ) {
		return $$$rDNE
	}
	set n = $$$clients(request.Client,"name")
	set result = $$$rBULK(n)
	return result
}

Method SELECT(request As redis.Request) As redis.Response [ Private ]
{
	set ns=$list(request.Arguments,1)
	if ( '##class(%SYS.Namespace).Exists(ns) ) {
		set result = $$$rERROR("Namespace does not exist")
		return
	}
	set $$$clients(request.Client,"db")=ns
	set $$$control("db",ns)=""	// mark this namespace a being used
	$$$TRACE("SELECT client="_client_" ns="_ns)
	return $$$rOK
}

Method SET(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)'=2 ) {
		return $$$rERROR("SET invalid request.Arguments")
    }
	set key=$list(request.Arguments,1),value=$list(request.Arguments,2)
    set $$$keys(key)=$replace(value,",","___44___")		// encode commas
    $$$TRACE("SET key="_key_" value="_value)
    return $$$rOK
}

Method MSET(request As redis.Request) As redis.Response [ Private ]
{
	if ( ($listlength(request.Arguments)#2)'=0 ) {
		return $$$rERROR("SET invalid request.Arguments")
    }
    for i=1:2:$listlength(request.Arguments) {
		set key=$list(request.Arguments,i)
		set value=$list(request.Arguments,i+1)
		set $$$keys(key)=value
	}
	return $$$rOK
}

Method HSET(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)'=3 ) {
		return $$$rERROR("SET invliad request.Arguments")
    }
	$$$TRACE("HSET")
    set hash=$listget(request.Arguments,1)
    set key=$listget(request.Arguments,2)
    set value=$listget(request.Arguments,3)
    $$$TRACE("HSET hash="_hash_" key="_key_" value="_value)
    set $$$hashes(hash,key)=value
    return $$$rOK
}

Method HSETNX(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)'=3 ) {
		return $$$rERROR("SET invliad request.Arguments")
    }
    $$$TRACE("HSETNX")
    set hash=$listget(request.Arguments,1)
    set key=$listget(request.Arguments,2)
    set value=$listget(request.Arguments,3)
    $$$TRACE("HSET hash="_hash_" key="_key_" value="_value)
    if ( '$data( $$$hashes(hash,key) ) ) {  // only set if does NOT exist!
    	set $$$hashes(hash,key)=value
	return $$$rINT(1)
    }
    // field exists, do nothing & return 0
    return $$$rINT(0)
}

Method HINCRBY(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)'=3 ) {
	return $$$rERROR("HINCRBY invliad request.Arguments")
    }
    $$$TRACE("HINCRBY")
    set hash=$listget(request.Arguments,1)
    set key=$listget(request.Arguments,2)
    set value=+$listget(request.Arguments,3)  // convert to int implicit!
    $$$TRACE("HSET hash="_hash_" key="_key_" value="_value)
    // exist or not, the key is convert to number
    set $$$hashes(hash,key)=+$get($$$hashes(hash,key))+value
    return $$$rINT( $$$hashes(hash,key) )
}

Method HINCRBYFLOAT(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)'=3 ) {
	return $$$rERROR("HINCRBYFLOAT invliad request.Arguments")
    }
    $$$TRACE("HINCRBYFLOAT")
    set hash=$listget(request.Arguments,1)
    set key=$listget(request.Arguments,2)
    set value=+$listget(request.Arguments,3)  // convert to int implicit!
    $$$TRACE("HSET hash="_hash_" key="_key_" value="_value)
    // exist or not, the key is convert to number
    set $$$hashes(hash,key)=+$get($$$hashes(hash,key))+value
    return $$$rBULK( $$$hashes(hash,key) )
}

Method HMSET(request As redis.Request) As redis.Response [ Private ]
{
    if ( $listlength(request.Arguments)<3 ) {
	return $$$rERROR("HMSET invalid request.Arguments")
    }
    // Error here if not even number of key/value pairs
    // the number of args should be at least 3 and ODD
    if ( ($listlength(request.Arguments)#2)'=1 ) {  //'
		return $$$rERROR("HMSET invalid request.Arguments")
    }
 
    $$$TRACE("HMSET")
    set hash=$listget(request.Arguments,1)
    for i=2:2:$listlength(request.Arguments) {
        set key=$listget(request.Arguments,i)
        set value=$listget(request.Arguments,i+1)
        $$$TRACE("HMSET hash="_hash_" key="_key_" value="_value)
        set $$$hashes(hash,key)=value
    }
    return $$$rOK
}

Method APPEND(request As redis.Request) As redis.Response [ Private ]
{
    set key=$list(request.Arguments,1)
    set val=$list(request.Arguments,2)
    $$$TRACE("APPEND key="_key_" val="_val_" old="_$get($$$keys(key)))
    set $$$keys(key)=$get($$$keys(key))_val
  	return $$$rOK
}

Method EXISTS(request As redis.Request) As redis.Response [ Private ]
{
    set key=$list(request.Arguments,1)
    $$$TRACE("EXISTS key="_key)
    if ( $data( $$$keys(key) ) ) {
		return $$$rINT(1)
    } else {
		return $$$rINT(0)
    }
}

Method HEXISTS(request As redis.Request) As redis.Response [ Private ]
{
    set key=$list(request.Arguments,1),field=$list(request.Arguments,2)
    $$$TRACE("HEXISTS key="_key_" field="_field)
    if ( $data( $$$hashes(key,field) ) ) {
	return $$$rINT(1)
    } else {
	return $$$rINT(0)
    }
}

Method DEL(request As redis.Request) As redis.Response [ Private ]
{
	set keysDeleted = 0
	for i=1:1:$listlength(request.Arguments) {
	    set key=$list(request.Arguments,i)
    	$$$TRACE("DEL key="_key)
    	if ( '$data($$$keys(key)) ) {  //'
			$$$TRACE("DEL key does not exist")
			continue	
    	}
    	// TODO: Lock before kill, check $Test, etc
    	kill $$$keys(key)
		set keysDeleted = keysDeleted + 1
    }
	set result=$$$rINT(keysDeleted)
    $$$TRACE("DEL result="_result.toString())
    return result
}

Method GETWildKey(request As redis.Request) As redis.Response [ Private ]
{
	set key = $list(request.Arguments,1)
	set keyPrefix = $piece(key,"*",1),keySuffix=$piece(key,"*",*)
	set cKey = $replace(key,"*",".*")
	set k=$order($$$keys(keyPrefix))
	set values = $listbuild(),i=0
	while ( k'="" ) {
		if ( '$match(k,cKey) ) { quit }
		set $list(values,$increment(i))=$$$keys(k)
		set k=$order($$$keys(k))
	}
	set result = $$$rBULK(values)
	$$$TRACE("GETWildCard result = " _ result.toString() )
	return result
}

Method GET(request As redis.Request) As redis.Response [ Private ]
{
	
    set key=$list(request.Arguments,1)
    if (key[..#KeyWildcard) {
	    return ..GETWildKey(request)
    }
    $$$TRACE("GET key="_key)
    if ( '$data($$$keys(key)) ) {   //'
		$$$TRACE("GET key does not exist")
		return $$$rDNE
    }
	set value=$$$keys(key)
    $$$TRACE("GET key="_key_" value="_value)
	if ( value?.N ) {
		set result = $$$rINT(value)   // integer
	} else {
	    set result=$$$rBULK(value)
	}
	$$$TRACE("GET result="_result.toString())
	return result
}

/// Returns the string representation of the type of the value stored at key. 
/// The different types that can be returned are: string, list, set, zset and hash.
Method TYPE(request as redis.Request) as redis.Response [ Private ]
{
    set key=$list(request.Arguments,1)
    if ( '$data($$$keys(key)) ) {   //'
		$$$TRACE("GET key does not exist")
		return $$$rDNE
    }
	set value=$get($$$keys(key))	
	if ( $listvalid(value) && $listdata(value) ) {
		return $$$rBULK("list")
	}
	if ( value ? 1.N ) {
		if ( $data($$$sets(key)) = 11 ) { 	//set
			return $$$rBULK("set")
		} else {
			return $$$rBULK("integer")
		}
	} else {
		if ( $order($$$hashes(key,"")) '= "" ) { //'
			return $$$rBULK("hash")
		} else {
			return $$$rBULK("string")
		}
	}
	return $$$rERROR("Unknown type")
}

Method GETRANGE(request As redis.Request) As redis.Response [ Private ]
{
    set key=$list(request.Arguments,1)
    if ( '$data($$$keys(key)) ) { //'
		$$$TRACE("GETRANGE key does not exist")
		return $$$rDNE
    }
	set value=$$$keys(key)
    $$$TRACE("GETRANGE key="_key_" value="_value)
    set start=$list(request.Arguments,2),end=$list(request.Arguments,3)
    set value=$extract(value,start,end)
    $$$TRACE("GETRANGE start="_start_" end="_end_" value="_value)
    if ( value?.N ) {
		set result = $$$rINT(value)   // integer
    } else {
	    set result=$$$rBULK(value)
	}
	return result
}

Method HDEL(request As redis.Request) As redis.Response [ Private ]
{
    set hash=$list(request.Arguments,1)
    if ( '$data($$$hashes(hash)) ) {
		$$$TRACE("HDEL hash="_hash_" does not exist")
		return $$$rINT(0)
    }
    for i=2:1:$listlength(request.Arguments) {
		set field=$listget(request.Arguments,i)
		if ( $data($$$hashes(hash,field) ) ) {
			// TODO: Lock?
			$$$TRACE("HDEL removing "_hash_"."_field)
			kill $$$hashes(hash,field)
			set x=$increment(removedFieldCount)
		}
    }
    set result = $$$rINT(removedFieldCount)   // integer
    return result
}

Method HGET(request As redis.Request) As redis.Response [ Private ]
{
    set hash=$list(request.Arguments,1),field=$list(request.Arguments,2)
    if ( '$data($$$hashes(hash,field)) ) {
		$$$TRACE("HGET hash="_hash_" field="_field_" does not exist")
		return $$$rDNE
    }
	set value=$$$hashes(hash,field)
    $$$TRACE("HGET hash="_hash_" field="_field_" value="_value)
	if ( value?.N ) {
		set result = $$$rINT(value)   // integer
	} else {
	    set result=$$$rBULK(value)
	}
	return result
}

Method HLEN(request As redis.Request) As redis.Response [ Private ]
{
    set hash=$list(request.Arguments,1)
    if ( '$data($$$hashes(hash)) ) {
		$$$TRACE("HGET hash="_hash_" does not exist")
		return $$$rERROR("hash '"_hash_"' does not exist")
    }
    set key=$order($$$hashes(hash,""))
    while ( key'="" ) {
		set x=$increment(keyCount)
		set key=$order($$$hashes(hash,key))
    }
    set result=$$$rINT(keyCount)
    return result
}

Method HKEYS(request As redis.Request) As redis.Response [ Private ]
{
    set hash=$list(request.Arguments,1)
    if ( '$data($$$hashes(hash)) ) {
		$$$TRACE("HGET hash="_hash_" does not exist")
		return $$$rERROR("hash '"_hash_"' does not exist")
    }
    set key=$order($$$hashes(hash,""))
    while ( key'="" ) {
		set $list(keys,$increment(keyCount))=key
		set key=$order($$$hashes(hash,key))
    }
    set result=$$$rBULK(keys)
    return result
}

Method HMGET(request As redis.Request) As redis.Response [ Private ]
{
    set hash=$list(request.Arguments,1)
    if ( '$data($$$hashes(hash)) ) {
		$$$TRACE("HGET hash="_hash_" does not exist")
		return $$$rDNE
    }
    for i=2:1:$listlength(request.Arguments) {
		set field=$list(request.Arguments,i)
		if ( $data( $$$hashes(hash,field) ) ) {
			set value=$$$hashes(hash,field)
        	$$$TRACE("HMGET hash="_hash_" field="_field_" value="_value)
			set $list(values,i-1)=value
		}  // NOTE! non-exists fields map to (nil) list elements
    }
    set result=$$$rBULK(values)
    return result
}

Method HGETALL(request As redis.Request) As redis.Response [ Private ]
{
	set hash=$list(request.Arguments,1)
	set field=$order($$$hashes(hash,""))
	$$$TRACE("HGETALL hash="_hash_" field="_field)
	set counter=0
	while ( field'="" ) {
		// key
		set $list(results,$i(counter)) = field
		// value
		set value = $$$hashes(hash,field)
		set $list(results,$i(counter)) = value 
		set field=$order($$$hashes(hash,field))
	}
	$$$TRACE("HGETALL results="_$listtostring(results))
	set result = $$$rBULK(results)
	$$$TRACE("HGETALL result="_result.toString())
	return result
}

Method GETSET(request As redis.Request) As redis.Response [ Private ]
{
    set getResult=..GET(request)
    $$$TRACE("GETSET getResult="_getResult.toString())
    set setResult=..SET(request)
    $$$TRACE("GETSET setResult="_setResult.toString())
    return getResult
}

Method INCR(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set i=$i($$$keys(key))
	$$$TRACE("INCR key="_key_" value="_i)
	return $$$rINT(i)
}

Method INCRBY(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set by=$list(request.Arguments,2)
	set i=$i($$$keys(key),by)
	$$$TRACE("INCRBY key="_key_" value="_i)
	return $$$rINT(i)
}

Method DECR(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set i=$i($$$keys(key),-1)
	$$$TRACE("DECR key="_key_" value="_i)
	return $$$rINT(i)
}

Method DECRBY(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set by=$list(request.Arguments,2)
	set i=$i($$$keys(key),-by)
	$$$TRACE("DECRBY key="_key_" value="_i)
	return $$$rINT(i)
}

Method LINDEX(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set index=$list(request.Arguments,2)
	if ( '$data($$$lists(key)) ) {i  //'
		//nil
		return $$$rDNE
	}
	if ( '$listvalid($$$lists(key)) ) { //'
		return $$$rDNE
	}
	// valid index range, redis uses 0-based index, caché 1-based
	set cindex = index + 1
	/*
	if ( index >= 0 ) { set cindex = index + 1 }
	if ( index = -1 ) { set cindex = "*-0" }
	if ( index < -1 ) { set cindex = "*"_(index+1) }
	*/
	set length=$listlength($$$lists(key))
	if ( cindex > length ) {
		return $$$rDNE 		// nil  $$$rDNE??
	}
	if ( ( cindex < 0 ) && ( -cindex > length ) ) {
		return $$$rDNE
	}
	set ^x($i(^x))=$lb(index,cindex)
	if ( cindex > 0 ) {
		set value=$list($$$lists(key),cindex)
	} else {   // cindex <= 0 
		set value = $list($$$lists(key),*-(-cindex))
	}
	return $$$rBULK(value)
}

Method LLEN(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	if ( '$data($$$lists(key)) ) {i  //'
		//nil
		return $$$rDNE
	}
	if ( '$listvalid($$$lists(key)) ) { //'
		return $$$rDNE
	}
	set i=$listlength($$$lists(key))
	return $$$rINT(i)
}

Method LPUSH(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set value=$list(request.Arguments,2)
	$$$TRACE("LPUSH key="_key_" value="_value)
	set $$$lists(key)=$lb(value)_$get($$$lists(key))
	return $$$rINT($listlength($$$lists(key)))
}

Method LPOP(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	if ( '$listdata($$$lists(key) ) ) {
		//nill
		return $$$rDNE
	}
	set value=$list($$$lists(key),1)
	set $list($$$lists(key),1,1)=""	// remove first element
	set result=$$$rBULK(value)
}

Method LRANGE(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	if ( '$data($$$lists(key) ) ) {
		return $$$rDNE
	}
	$$$TRACE("LRANGE key="_key_" request="_request.toString())
	if ( $listlength(request.Arguments) '= 3 ) {
		return $$$rERROR("LRANGE needs start,stop parameters")
	}
	set start=+$list(request.Arguments,2),stop=+$list(request.Arguments,3)
	$$$TRACE("LRANGE start="_start_" stop="_stop)
	//set emptyListResult="*0"_$$$CRLF
	if ( start > $listlength($$$lists(key)) ) {
		//set result=emptyListResult
		return $$$rBULK($lb())
	}
	if ( stop > $listlength( $$$lists(key) ) ) {
		set stop=$listlength( $$$lists(key) )
	}
	set range=$list($$$lists(key),start,stop),result=""
	$$$TRACE("LRANGE range="_$listtostring(range))
	return $$$rBULK(range)
}

Method RPUSH(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set value=$list(request.Arguments,2)
	$$$TRACE("RPUSH key="_key_" value="_value)
#if $ZV["2013.2"
	set $list($$$lists(key),*+1)=value
#else
	set $$$lists(key)=$$$lists(key)_$lb(value)
#endif
	return $$$rINT($listlength($$$lists(key)))
}

Method RPOP(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	if ( '$listdata($$$lists(key) ) ) {
		//nill
		return $$$rDNE
	}
#if $ZV["2013.2"
	set value=$list($$$lists(key),*)
#else
	set value=$list($$$lists(key),$listlength($$$lists(key)))
#endif
	set length=$listlength($$$lists(key))
	set $list($$$lists(key),length,length)=""	// remove last element
	return $$$rBULK(value)
}

/// '
Method SADD(request As redis.Request) As redis.Response [ Private ]
{
	set key=$list(request.Arguments,1)
	set numToAdd=$listlength(request.Arguments)-1
	$$$TRACE("SADD key="_key_" numToAdd="_numToAdd_" request.Arguments="_$listtostring($list(request.Arguments,2,$ll(request.Arguments))))
	for i=1:1:numToAdd {
		set e=$list(request.Arguments,i+1)
		if ('$data($$$sets(key,e))) {  //'
		 set x=$i($$$sets(key))
		 set $$$sets(key,e)=""
		}
	}
	return $$$rINT($$$sets(key))
}

Method DBSIZE(request As redis.Request) As redis.Response [ Private ]
{
	set k=$order($$$keys("")),count=0
	while ( k'="" ) {
		set count = count + 1
		set k=$order($$$keys(k))
	}
	return $$$rINT(count)
}

Method TTL(request As redis.Request) As redis.Response [ Private ]
{
	// remove and return a random element from a set
	set key=$list(request.Arguments,1)
	if ( '$data($$$sets(key) ) ) {
		//nill
		return $$$rINT(-2)
	}
	$$$TRACE("TTL - not implemented yet - always returns -1 for no expire")
	return $$$rINT(-1)
}

Method SCARD(request As redis.Request) As redis.Response [ Private ]
{
	// remove and return a random element from a set
	set key=$list(request.Arguments,1)
	if ( '$data($$$sets(key) ) ) {
		//nill
		return $$$rDNE
	}
	return $$$rINT($$$sets(key))
}

Method SPOP(request As redis.Request) As redis.Response [ Private ]
{
	// remove and return a random element from a set
	set key=$list(request.Arguments,1)
	if ( '$data($$$sets(key) ) ) {
		//nill
		return $$$rDNE
	}
	set r=$random($$$sets(key))+1,value=$order($$$sets(key,""))
	for i=1:1:(r-1) set value=$order($$$sets(key,value))
	$$$TRACE("r="_r_" value="_value)
	set x=$increment($$$sets(key),-1)
	if ( x=0 ) { 
		kill $$$sets(key) 
	} else {
		kill $$$sets(key,value)
	}
	return $$$rBULK(value)
}

Method SMEMBERS(request As redis.Request) As redis.Response [ Private ]
{
	$$$TRACE("SMEMEBERS args="_$listtostring(request.Arguments))
	set key=$list(request.Arguments,1)
	if ( '$data($$$sets(key) ) ) {
		//nill
		return $$$rDNE
	}
	set value=$order($$$sets(key,"")),values=""
	while ( value'="" ) {
		set values=values_$lb(value)
		set value=$order($$$sets(key,value))
	}
	$$$TRACE("SMEMBERS values="_$listtostring(values))
	return $$$rBULK(values)
}

//'
Method INFO(request As redis.Request) As redis.Response [ Private ]
{
	// NOTE! NO commas "," allowed in the INFO string
	// otherwise the response won't get written out as one big string'
	set $list(xr,1)="# Server"
	set $list(xr,2)="cache_redis_server_version:"_$$$VERSION
	set $list(xr,3)="os:"_$ZV
	set $list(xr,4)="timestamp:"_$zdt($zts)
	set $list(xr,5)="process_id:"_$system.SYS.ProcessID()
	set $list(xr,6)="used_memory_human:"_$piece($view(-1,$job),"^",17)	
	set $list(xr,7)=" "
	set $list(xr,8)="# redis.conf"
	set key=$order($$$conf(""))
	set xri=8
	while ( key'="" ) {
		set $list(xr,$increment(xri))=key_":"_$$$conf(key)
		set key=$order($$$conf(key))
	}
	set ixr = $listtostring(xr,$c(13,10))
	set result=$$$rBULK(ixr)
	$$$TRACE("INFO result="_result.toString())
	return result
}

Method KEYSWildKey(request As redis.Request) As redis.Response 
{
	set key = $list(request.Arguments,1)
	set keyPrefix = $piece(key,"*",1),keySuffix=$piece(key,"*",*)
	set cKey = $replace(key,"*",".*")
	set k=$order($$$keys(keyPrefix))
	set i=0,values=$listbuild()
	while ( k'="" ) {
		$$$TRACE("k="_k)
		if ( '$match(k,cKey) ) { quit }
		set $list(values,$increment(i))=k
		set k=$order($$$keys(k))
	}
	if ( $listdata(values) ) {
		set result = $$$rBULK(values)
	} else {
		//set result = $$$rDNE
		set result = $$$rBULK($lb())
	}
	$$$TRACE("GETWildCard result = " _ result.toString() )
	return result
}


Method KEYS(request As redis.Request) As redis.Response [ Private ]
{
	$$$TRACE("KEYS command - wildcard, pattern matching not implemented")
	set (oq,q)=$listget(request.Arguments,1,"*"),mode=1
	$$$TRACE("KEYS q="_q_" mode="_mode)
	if (q[..#KeyWildcard) {
	    return ..KEYSWildKey(request)
    }
	if ( q["?" ) {
		set q=$tr(q,"?","*"),mode=2
	}
	if ( q["[" ) {
		set q=$p(q,"[",1)_"*"_$p(q,"]",2),mode=3
	}
	kill r
	set key=$order($$$keys(""))
	while ( key'="" ) {	
		set r($i(r))=key
		$$$TRACE("r("_r_")="_r(r))
		set key=$order($$$keys(key))
	}
	merge s=r
	$$$TRACE("s="_s)
	if ( mode = 2 ) {
		for i=1:1:r {
			if ( $l(r(i))'=$l(oq) ) {
				set s=s-1
				kill s(i)
			}
		}
	}
	
	if ( mode = 3 ) { 		// to-do
		return $$$rERROR("Not implemented")
	}
	
	
	set results=$lb()
	set i=$order(s(""))
	while ( i'="" ) {
		set v=s(i)
		set results=results_$lb(v)
		set i=$order(s(i))
	}
	set result=$$$rBULK(results)
	$$$TRACE(result)
	return result
}

}
