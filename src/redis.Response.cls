Include Ensemble

Class redis.Response Extends %Persistent
{

Parameter STATUS = "+";

Parameter ERROR = "-";

Parameter INTEGER = ":";

Parameter BULK = "$";

Parameter MULTIBULK = "*";

Property Type As %String [ MultiDimensional, Private ];

Property Request As redis.Request;

Method %OnNew(type) As %Status
{
	if ( $data(type) ) {
		set $this.Type = type
	} else {
		set $this.Type = ""
	}
	return $$$OK
}

Property Args As %List [ InitialExpression = {$listbuild()}, MultiDimensional ];

Method toString() As %String
{
	set c=$get(..Type,"type?")
	if ( $listvalid(..Args) ) {
		if ( $listdata(..Args) ) {
			set l=$listtostring(..Args)
		} else {
			set l=""
		}
	} else {
		set l=..Args
	}
	return "Type"_c_" Args="_l
}

ClassMethod OK(ByRef response As %String = "OK", ByRef req As redis.Request) As redis.Response
{
	set r=##class(redis.Response).%New(..#STATUS)
	set r.Args=$lb(response)
	set r.Request = req
	return r
}

ClassMethod Error(msg As %String, ByRef req As redis.Request) As redis.Response
{
	set r=##class(redis.Response).%New(..#ERROR)
	set r.Args=$lb(msg)
	set r.Request=req
	return r
}

ClassMethod Int(i As %Integer, ByRef req As redis.Request) As redis.Response
{
	set r=##class(redis.Response).%New(..#INTEGER)
	set r.Args=$lb(i)
	set r.Request = req
	return r
}

ClassMethod Bulk(args As %List, ByRef req As redis.Request) As redis.Response
{
	set r=##class(redis.Response).%New()
	$$$TRACE("Bulk() args=" _ args)
	if ( $listvalid(args) ) {
		set r.Args=args
	} else {
		if ( args["," ) {
			set r.Args=$listfromstring(args)
		} else {
			// simple string value, decode coded commas
			set r.Args=$listbuild($replace(args,"___44___",","))
		}
	}
	set r.Request=req
	return r
}

// Method writeToStream(ByRef stream As %Stream)

Method writeToStream(stream) As %Status
{
	break
	set status = $$$OK
	// is status?
	if ( $this.Type = $this.#STATUS ) {
		$$$TRACE("writeToStream #STATUS:"_$list($this.Args,1))
		do stream.WriteLine( $this.#STATUS _ $list($this.Args,1),1,.status )
		return status
	}
	// is error?
	if ( $this.Type = $this.#ERROR ) {
		do stream.WriteLine( $this.#ERROR _ $list($this.Args,1),1,.status )
		return status

	}
	// is int?
	if ( $this.Type = $this.#INTEGER ) {
		do stream.WriteLine( $this.#INTEGER _ $list($this.Args,1),1,.status )
		return status
	}
	set argCount = $listlength($this.Args)
	if ( argCount > 1 ) { // MultiBulk
		do stream.WriteLine( $this.#MULTIBULK _ argCount,1,.status )
		return:$$$ISERR(status) status
		break
		for i=1:1:argCount {
			if ( $listdata($this.Args,i) ) {
				set data=$list($this.Args,i)
				$$$TRACE("data="_data_" $length(data)="_$length(data))
				if ( data?.N ) { // integer
				  do stream.WriteLine( $this.#INTEGER _ data,1,.status)
				  quit:$$$ISERR(status)
				} else {	
				  do stream.WriteLine( $this.#BULK _ $length(data),1,.status)
				  quit:$$$ISERR(status)
				  do:$l(data)>0 stream.WriteLine( data,1,.status )
				  quit:$$$ISERR(status)
				}
			} else {
				do stream.WriteLine( $this.#BULK _ "-1",1,.status )
				quit:$$$ISERR(status)
			}
		}
		return:$$$ISERR(status) status
	} else { // Bulk
		if ( $listdata($this.Args,1) ) {	
			set data=$list($this.Args,1)
			do stream.WriteLine( $this.#BULK _ $length(data),1,.status)
			return:$$$ISERR(status) status
			do:$l(data)>0 stream.WriteLine( data,1,.status )
			return:$$$ISERR(status) status
		} else {
			//do stream.WriteLine( $this.#BULK _ "0",1,.status )
			do stream.WriteLine( $this.#BULK _ "-1",1,.status )
			return:$$$ISERR(status) status
		}
	}
	return status
}

<Storage name="Default">
<Data name="ResponseDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Type</Value>
</Value>
<Value name="3">
<Value>Args</Value>
</Value>
<Value name="4">
<Value>Request</Value>
</Value>
</Data>
<DataLocation>^redis.ResponseD</DataLocation>
<DefaultData>ResponseDefaultData</DefaultData>
<ExtentSize>100000</ExtentSize>
<IdLocation>^redis.ResponseD</IdLocation>
<IndexLocation>^redis.ResponseI</IndexLocation>
<SequenceNumber>17</SequenceNumber>
<StreamLocation>^redis.ResponseS</StreamLocation>
<Type>%Library.CacheStorage</Type>
</Storage>
}

