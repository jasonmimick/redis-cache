# Unit tests for ensredis, redis-ens (redis-cache)
# Call and assert each command we support
require "rubygems"
require "redis"

channels = %w(  football
		music
		news
	)


redis = Redis.new( :host => "healthshare.us", :port => 6379)
redis.publish("football","Huskers Dominate!")
redis.publish("football","Redskins Victory")
redis.publish("music","Rolling Stones to retire")
redis.publish("news","Income Tax Abolished")


