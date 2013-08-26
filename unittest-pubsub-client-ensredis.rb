# Unit tests for ensredis, redis-ens (redis-cache)
# Call and assert each command we support
require "rubygems"
require "redis"

channels = %w(  football
		music
		news
	)


$redis = Redis.new( :host => "healthshare.us", :port => 6379)

puts "Going to listen to channels football, music and news"
$redis.subscribe('football','music','news') do |on| 
	on.message do |channel,msg|
		puts "channel=#{channel} msg-#{msg}"
	end
end

