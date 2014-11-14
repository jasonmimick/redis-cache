# Unit tests for ensredis, redis-ens (redis-cache)
# Call and assert each command we support
require "rubygems"
require "redis"

# redis = Redis.new( :host => "healthshare.us", :port => 6379)
redis = Redis.new( :host => "localhost", :port => 6379)

#DEL
del = redis.del("incr")
puts "DEL => #{del}"

#INCR
incr = redis.incr("incr")
puts "INCR incr=#{incr}"

#INCRBY
incr = redis.incrby("incr",1000)
puts "INCRBY 1000, incr=#{incr}"

#DECR
incr = redis.decr("incr")
puts "DECR incr=#{incr}"

#DECRBY
incr = redis.decrby("incr",1000)
puts "DECRBY 1000, incr=#{incr}"

puts "incr should be 0, it is #{incr}"

#SET
set = redis.set("intkey",123456)
puts "SET intkey=#{set}"

#GET
intkey = redis.get("intkey")
puts "GET intkey=#{intkey}"

#SET
set = redis.set("stringkey","Thirty two teeth in a jawbone Alabama cryin for none Before I have to hit him I hope he's got the sense to run")
puts "SET stringkey=#{set}"

#GET
stringkey = redis.get("stringkey")
puts "GET stringkey=#{stringkey}"

#EXISTS
stringkeyexists = redis.exists("stringkey")
puts "EXISTS stringkeyexists=#{stringkeyexists}"
puts "EXISTS keyshouldnotexists=#{redis.exists("keyshouldnotexist")}"

#GETRANGE
puts "GETRANGE firstLine(0,29)=#{redis.getrange("stringkey",0,29)}"
puts "GETRANGE firstLine(0,10000)=#{redis.getrange("stringkey",0,10000)}"
puts "GETRANGE firstLine(500,700)=#{redis.getrange("stringkey",500,700)}"
puts "GETRANGE firstLine(50,7)=#{redis.getrange("stringkey",50,7)}"

#GETSET
oldval = redis.getset("intkey",50)
puts "GETSET oldval=#{oldval}, newval=#{redis.get("intkey")}"

#HSET
hset = redis.hset("hash1","field1","value1")
puts "HSET hset=#{hset}"

#HGET
puts "HGET hash1.field1=#{redis.hget("hash1","field1")}"

#HMSET
hmset = redis.hmset("hash1","field2","value2","field3",12345,"field4","field 4 field 4 field 4")
puts "HMSET hmset=#{hmset}"

#HMGET
hmget=redis.hmget("hash1","field1","field3","field4")
puts "HMGET hash1.field1, hash1.field3, hash1.field4"
puts hmget.inspect

#HGETALL
puts "HGETALL hash1"
puts redis.hgetall("hash1").inspect

#HKEYS
puts "HKEYS hash1",redis.hkeys("hash1").inspect
begin
	puts "HKEYS NonExistingHash"
	puts redis.hkeys("NonExistingHash").inspect
rescue 
	puts "Got error as expected"
end

#HEXISTS
puts "HEXISTS hash1.field3 exists=#{redis.hexists("hash1","field3")}"

#HLEN
puts "HLEN hash1=#{redis.hlen("hash1")}"
#HDEL
puts "HDEL hash1.field3=#{redis.hdel("hash1","field3")}"
puts "HEXISTS hash1.field3 exists=#{redis.hexists("hash1","field3")}"
puts "HLEN hash1=#{redis.hlen("hash1")}"

#HINCRBY
puts "HSET hash1.int1=5 ->#{redis.hset("hash1","int1",5)}"
puts "HINCRBY hash1.int1,10 ->#{redis.hincrby("hash1","int1",10)}"
puts "HGET hash1.int1=#{redis.hget("hash1","int1")}"
puts "HINCRBY hash1.int1,-8 ->#{redis.hincrby("hash1","int1",-8)}"
puts "HGET hash1.int1=#{redis.hget("hash1","int1")}"

puts "HSET hash1.nonint='fee' ->#{redis.hset("hash1","nonint","fee")}"
puts "HGET hash1.nonint=#{redis.hget("hash1","nonint")}"
puts "HINCRBY hash1.nonint,1 ->#{redis.hincrby("hash1","nonint",1)}"
puts "HGET hash1.nonint=#{redis.hget("hash1","nonint")}"

#HINCRBYFLOAT
puts "HSET hash2.mykey=10.50 ->#{redis.hset("hash2","mykey",10.50)}"
puts "HGET hash2.mykey=#{redis.hget("hash2","mykey")}"
puts "HINCRBYFLOAT hash2.mykey,0.1 ->#{redis.hincrbyfloat("hash2","mykey",0.1)}"

puts "HSET hash2.mykey=5.0e3 ->#{redis.hset("hash2","mykey",5.0e3)}"
puts "HGET hash2.mykey=#{redis.hget("hash2","mykey")}"
puts "HINCRBYFLOAT hash2.mykey,2.0e2->#{redis.hincrbyfloat("hash2","mykey",2.0e2)}"

#HSETNX
puts "HSETNX myhash,field='Hello' ->#{redis.hsetnx("myhash","field","Hello")}"
puts "HSETNX myhash,field='World' ->#{redis.hsetnx("myhash","field","World")}"
puts "HGET myhash.field=#{redis.hget("myhash","field")}"
