Class redis.Tests Extends %RegisteredObject
{

ClassMethod writeAndRewind(stream As %Stream, data As %List)
{
	set status=$$$OK
	for i=1:1:$listlength(data) {
		do stream.WriteLine( $list(data,i),1,.status )
		do:$$$ISERR(status) $system.OBJ.DisplayError(status)
	}
	do stream.Rewind()
}

ClassMethod pingTest()
{
	set baseStream=##class(%IO.StringStream).%New()
	set baseStream.LineTerminator=$C(13,10)
	set stream=##class(%IO.MetaCharacterStream).%New(baseStream)
	
	
	write "PING",!
	set data=$listbuild("*1","$4","PING")
	do ..writeAndRewind(stream,data)
	set sc=##class(redis.Request).readFromStream(.stream,.req)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
	write req.toString(),!
	zw req
	
	#dim response as redis.Response
	
	set response=##class(redis.Response).OK(,.req)
	set sc=response.writeToStream(stream)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
	do stream.OutputToDevice()
	zw response
	write response.toString(),!
}

ClassMethod testRequest()
{
	set baseStream=##class(%IO.StringStream).%New()
	set baseStream.LineTerminator=$C(13,10)
	set stream=##class(%IO.MetaCharacterStream).%New(baseStream)
	
	
	write "SET mykey myvalue",!
	set data=$listbuild("*3","$3","SET","$5","mykey","$7","myvalue")
	do ..writeAndRewind(stream,data)
	set sc=##class(redis.Request).readFromStream(.stream,.req)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
	write req.toString(),!
	zw req
	#dim response as redis.Response
	
	set response=##class(redis.Response).OK(,.req)
	set sc=response.writeToStream(stream)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
	do stream.OutputToDevice()
	zw response
	
	write !,"GET mykey",!
	do stream.Clear()
	set data=$lb("*2","$3","GET","$5","mykey")
	do ..writeAndRewind(stream,data)	
	set sc=##class(redis.Request).readFromStream(.stream,.req)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)

	zw req
	set response=##class(redis.Response).Bulk("myvalue",.req)
	set sc=response.writeToStream(stream)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
 	zw response
	do stream.OutputToDevice()

	for i=1:1:3 {	
	write !,"SET key1 value1",!
		do stream.Clear()
		set data=$lb("*3","$3","SET","$4","key"_i,"$6","value"_i)
		do ..writeAndRewind(stream,data)	
		set sc=##class(redis.Request).readFromStream(.stream,.req)
     	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
		zw req
	}
	do stream.Clear()
	write "MGET key1 key2 nonexisting",!
	set data=$lb("*4","MGET","$4","key1","$4","key2","$11","nonexisting")
	do ..writeAndRewind(stream,data)	
	set sc=##class(redis.Request).readFromStream(.stream,.req)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)
	zw req

	set response=##class(redis.Response).Bulk($lb("value1","value2",),.req)
	set sc=response.writeToStream(stream)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)

 	zw response
	do stream.OutputToDevice()
	
	write "INLINE test",!
	write "EXISTS somekey",!
	do stream.Clear()
	set data=$lb("EXISTS somekey")
	do ..writeAndRewind(stream,data)	
	set sc=##class(redis.Request).readFromStream(.stream,.req)
	do:$$$ISERR(sc) $system.OBJ.DisplayError(sc)

	zw req
}

}

