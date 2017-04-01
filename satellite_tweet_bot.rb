#!/usr/bin/env ruby -Ku


# load library
require 'rubygems'
require 'twitter'
require 'time'
require 'roo'

# define logging script activity function
def logging( log_str )
  begin
    file = open(File.expand_path('../_log_tweets',__FILE__),'a')
    file.print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = true
  print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = false
  ensure
    file.close
  end
end

## Initialize
# Twitter gem configuration

logging("token files : token.conf")
client = Twitter::REST::Client.new do |config|
  conf = open(File.expand_path('../token.conf',__FILE__),'r')
  config.consumer_key        = conf.gets.chomp
  config.consumer_secret     = conf.gets.chomp
  config.access_token        = conf.gets.chomp
  config.access_token_secret = conf.gets.chomp
  conf.close
end

logging('Start: satellite_bot_tweet.rb started.')

fs = File::Stat.new(File.expand_path('../satellitelist.xlsx',__FILE__))
tsvtimestamp = fs.mtime - 1
tweetlist = Array.new()

begin

# loop wait for tweet
loop do

  # load tweet list
    fs = File::Stat.new(File.expand_path('../satellitelist.xlsx',__FILE__))
    if tsvtimestamp < fs.mtime  then
      tsvtimestamp = fs.mtime
      tweetlist.clear
      tweetlist = Array.new()
      errorcount = []
      xlsx = Roo::Excelx.new(File.expand_path('../tweetlist.xlsx',__FILE__))
      xlsx.default_sheet = 'todayssatellite'
      for xlsrow in 1..xlsx.last_row do
        tweetlist += [[ xlsx.cell(xlsrow,1),xlsx.cell(xlsrow,2) ]]
      end
      logging(' : Success: tweet list reloaded. list count is '+tweetlist.count.to_s)
    end

  # tweet list checks 3hour.(10800)
    loopcount = 0
    begin
      tweet = tweetlist.assoc(Time.now.strftime('%m/%d %H:%M:%S'))
      if tweet then
        begin
          
          begin
            client.update(tweet[1])
            ## catch exception ... rate_limit_over
          rescue Twitter::Error::TooManyRequests => error
            ## logging
            logging("Exception catch ( ", error,  " ) ... waiting until ", error.rate_limit.reset_at.to_s, "\n")
            ## wait rate_limit_reset
            sleep error.rate_limit.reset_in
            ## retry
            retry
          end
        logging('Execute: Twitter.update')
        rescue
          logging('Error: Twitter.update')
        end
      end
      sleep(1)
      loopcount = loopcount + 1
    end until loopcount >= 60
  end

ensure
  logging(' : Error: Daemon down.')
  fail
end
