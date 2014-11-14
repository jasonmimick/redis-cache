Include Ensemble

Class redis.Request Extends %Persistent
{

/// IP/port of client making the request
Property Client As %String;

Property IsInline As %Boolean [ InitialExpression = 0 ];

Property Command As %String [ MultiDimensional ];

Property Stream As %IO.DeviceStream;

Method CommandGet() As %String
{
	return $zconvert(i%Command,"U")
}

Property Arguments As %List [ InitialExpression = {$listbuild()}, MultiDimensional ];

Method toString() As %String
{
	set cc=$this.Command,aa=$this.Arguments
	set c=$get(cc,"command?")
	if ( $listdata(aa ) ) {
		set l=$listtostring(aa)
	} else {
		set l="empty"
	}
	return "Command="_c_" IsInline="_..IsInline_" Arguments="_l_" Client="_..Client
}

Method getChannelEvent(channel As %String) As %String
{
	return "^redis.channels("""_channel_""","""_$this.Client_""")"
}

ClassMethod processInlineBuffer(stream, firstLine, ByRef request As redis.Request) As %Status [ Private ]
{
	$$$TRACE("processInlineBuffer firstLine="_firstLine)
	set status=$$$OK
	set data=firstLine //stream.ReadLine()
	set args=$listfromstring(data," ")
	set request=##class(redis.Request).%New()
	set request.Command=$list(args,1)
	set request.Arguments=$list(args,2,$listlength(args))
	set request.IsInline=1
	return status
}

ClassMethod readFromStream(stream, Output request As redis.Request, Output timeout As %Numeric = -1) As %Status
{
	//break
	Set request=##class(redis.Request).%New()
	Set request.Stream = stream
	Set request.Command = ""
	//Set request.Client=$piece(stream.Remote,"|",2)
	set request.Arguments=$lb()
	set numArgsStr="",initialTimeout=timeout
	$$$TRACE("readFromStream initialTimeout="_initialTimeout_" timeout="_timeout)
	do {
		set timeout=initialTimeout
		set numArgsStr = stream.ReadLine(,.timeout,.status)
		if (timeout'=0) $$$TRACE("numArgsStr="_numArgsStr_" timeout="_timeout_" status="_status)
		Quit:(timeout'=0) 
		Quit:$$$ISERR(status) 
	} while ( numArgsStr="")
	Quit:(timeout'=0) $$$OK
	Quit:$$$ISERR(status) status

	if ( $extract(numArgsStr,1)'="*" ) { // Inline request
		return ..processInlineBuffer(stream,numArgsStr,.request)
	}
	set numArgs=$e(numArgsStr,2,*)
	if ( numArgs'?.N ) {
		throw ##class(%Exception.General).%New("Invalid Argument Count",,"numArgsStr='"_numArgsStr_"'")
	}
	$$$TRACE("numArgs="_numArgs)
	set cmdByteCount=""
	// From here on - we do not timeout!
	// since we already got the start of a command
	do {
		set cmdByteCount=stream.ReadLine(,,.status)
		$$$TRACE("cmdByteCount="_cmdByteCount)
	} while ( cmdByteCount="") 
	Quit:$$$ISERR(status) status
	do {
		set request.Command=stream.ReadLine(,,.status)
	} while ( request.Command="")
	$$$TRACE("request.Command="_request.Command_" status="_status)
	Quit:$$$ISERR(status) status
	for i=1:1:(numArgs-1) {
		set byteCount=""
		do {
			set byteCount = stream.ReadLine(,,.status)
		} while ( byteCount="")
		Quit:$$$ISERR(status)
		set arg=""
		do {
			set arg=stream.ReadLine(,,.status)
			quit:$$$ISERR(status)
		} while ( arg="" )
		set $list(request.Arguments,i)=arg
		
	}
	return status
}

<Storage name="Default">
<Data name="RequestDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Command</Value>
</Value>
<Value name="3">
<Value>Arguments</Value>
</Value>
<Value name="4">
<Value>IsInline</Value>
</Value>
<Value name="5">
<Value>Client</Value>
</Value>
<Value name="6">
<Value>Stream</Value>
</Value>
</Data>
<DataLocation>^redis.RequestD</DataLocation>
<DefaultData>RequestDefaultData</DefaultData>
<ExtentSize>100000</ExtentSize>
<IdLocation>^redis.RequestD</IdLocation>
<IndexLocation>^redis.RequestI</IndexLocation>
<SequenceNumber>11</SequenceNumber>
<StreamLocation>^redis.RequestS</StreamLocation>
<Type>%Library.CacheStorage</Type>
</Storage>
}

