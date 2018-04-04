#!/usr/bin/env ruby -Ku


# load library
require 'rubygems'
require 'twitter'
require 'time'
require 'roo'
require "net/http"
require "uri"
require 'open-uri'

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

# Slack post
def slackpost( raw_url, payload )
  uri = URI.parse(raw_url)
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request["Content-Type"] = "application/json"
  request.body = payload
  response = https.request(request)
end

## Initialize
# Twitter gem configuration

logging('Start: satellite_bot_tweet.rb started.')
logging("Opening token files : token.conf")
conf = open(File.expand_path('../token.conf',__FILE__),'r')
client = Twitter::REST::Client.new do |config|
  config.consumer_key        = conf.gets.chomp
  config.consumer_secret     = conf.gets.chomp
  config.access_token        = conf.gets.chomp
  config.access_token_secret = conf.gets.chomp
end
slackurl = conf.gets.chomp
conf.close

fs = File::Stat.new(File.expand_path('../tweetlist.xlsx',__FILE__))
tsvtimestamp = fs.mtime - 1
tweetlist = Array.new()

begin

  # loop wait for tweet
  loop do

  # load tweet list
    fs = File::Stat.new(File.expand_path('../tweetlist.xlsx',__FILE__))
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
      logging('Success: tweet list (re)loaded. list count is '+tweetlist.count.to_s)
    end

  # tweet list checks 3hour.(10800)
    loopcount = 0
    begin
      # make time vars
      tweettime_now = Time.now.strftime('%m/%d %H:%M:%S')
      tweettime_nex = (Time.now + (60*60*24)).strftime('%m/%d %H:%M:%S')
      # tweet
      tweet = tweetlist.assoc(tweettime_now)
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

      # next day tweet (slack)
      pretweet = tweetlist.assoc(tweettime_nex)
      if pretweet then
        begin
          prepayload = {
            "attachments" => [
              {
                "mrkdwn"  => true,
                "pretext" => "今日の人工衛星: 翌日ツイートの予告",
                "text"    => "以下のツイートが24時間後になされます\n#{pretweet[1]}",
                "mrkdwn_in" => [ "text" ],
                "color": "good"
              }
            ]
          }.to_json
          slackpost( slackurl, prepayload )
          logging('Execute: Slack.update')
        rescue => e
          logging('Error: Slack.update ' + e.message)
        end
      end

      sleep(1)
      loopcount = loopcount + 1
    end until loopcount >= 60
  end
ensure
  logging('Error: Daemon down.')
  fail
end
