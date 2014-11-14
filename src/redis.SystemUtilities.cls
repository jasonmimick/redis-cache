Include redis.redis

Class redis.SystemUtilities Extends %RegisteredObject
{

ClassMethod EnsureNamespace() As %Status
{
	$$$TRACE("ensureSN ns="_ns)
	return:##class(%SYS.Namespace).Exists(ns) $$$OK
	// On SELECT commands, ensure the requested namespace is available
	if ( ns?.N ) {
		set ns=$$$nsPrefix_ns	// support redis "0","1" dbs
	}
	$$$TRACE("ensureNS ns="_ns_" did not exist!")
	set dbname=ns
	new $namespace
	set $namespace="%SYS"
	set dbo=##class(Config.Databases).%OpenId(dbname)		
	if ( '$isobject(dbo) ) {
		$$$TRACE("dbo not an object, need to create db")
		set sc=..CreateDatabase(dbname)
		$$$TRACE(sc)
		if ($$$ISERR(sc) ) {
			//zn currNS
			return sc
		}
	}
	// db exist's, now create ns
	set p("Globals")=dbname
	set sc=##class(Config.Namespaces).Create(ns,.p)
	// create mappings for control structures
	$$$TRACE(sc)
	return sc
}

ClassMethod CreateDatabase(DBName As %String) As %Status
{
	set sc=$$$OK
	new $namespace
	set $namespace="%SYS"
	$$$debug("createDb dbname="_DBName)
	set dbNameU=$zconvert(DBName,"U")
	if ( ##class(Config.Databases).Exists(dbNameU,.db) ) {
		$$$debug("DB exists")
		return $$$OK
	} 
	set dir=$system.Util.ManagerDirectory()_DBName
	set dirExists=##class(%File).Exists(dir)
	$$$debug("dirExists="_dirExists)
	if ( 'dirExists ) {
		set created=##class(%File).CreateDirectory(dir)  
		$$$debug("created dir = "_created)
		if ( 'created ) {
			return $$$ERROR("Could not create directory '"_dir_"'")
		}
	}
	set p("Directory")=dir
	set p("Name")=DBName
	set sc=##class(Config.Databases).Create(DBName,.p)
	set dbo=##class(Config.Databases).Open(DBName)
	set sc=dbo.%Save()
	return:$$$ISERR(sc) sc
	
	set db=##class(SYS.Database).%New()
	set db.Directory=dir
	set sc=db.%Save()
	return sc
}

ClassMethod DeleteDatabase(DBName As %String) As %Status
{
	new $namespace
	set $namespace="%SYS"
	$$$TRACE("deleteDb dbname="_dbname)
	set result=##class(Config.Databases).Delete(dbname)
	$$$TRACE("deletDb result="_result)
	return result
}

}

