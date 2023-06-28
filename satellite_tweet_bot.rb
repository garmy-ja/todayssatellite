#!/usr/bin/env ruby -Ku


# load library
require 'rubygems'
#require 'twitter'
require 'time'
require 'roo'
require "net/http"
require "uri"
require 'open-uri'

# for API v2
require 'oauth'
require 'json'
require 'typhoeus'
require 'oauth/request_proxy/typhoeus_request'
require 'dotenv/load'

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

# Tweet post
create_tweet_url = "https://api.twitter.com/2/tweets"

def create_tweet(url, consumer_key, consumer_secret, access_token, access_token_secret, text)

    # OAuth Consumerオブジェクトを作成
    consumer = OAuth::Consumer.new(consumer_key, consumer_secret,
        :site => 'https://api.twitter.com',
        :debug_output => false)

    # OAuth Access Tokenオブジェクトを作成
    access_token = OAuth::AccessToken.new(consumer, access_token, access_token_secret)

    # OAuthパラメータをまとめたハッシュを作成
    oauth_params = {
        :consumer => consumer,
        :token => access_token,
    }

    json_payload = {"text": text}
	options = {
	    :method => :post,
	    headers: {
	     	"User-Agent": "v2CreateTweetRuby",
        "content-type": "application/json"
	    },
	    body: JSON.dump(json_payload)
	}
	request = Typhoeus::Request.new(url, options)
	oauth_helper = OAuth::Client::Helper.new(request, oauth_params.merge(:request_uri => url))
	request.options[:headers].merge!({"Authorization" => oauth_helper.header}) # Signs the request
	response = request.run

	return response
end

## Initialize

logging('Start: satellite_bot_tweet.rb started.')

# Twitter configuration
logging("Opening token files : .env")
Dotenv.load (File.expand_path('../.env',__FILE__))
consumer_key = ENV["CONSUMER_KEY"]
consumer_secret = ENV["CONSUMER_SECRET"]
access_token = ENV["ACCESS_TOKEN"]
access_token_secret = ENV["ACCESS_TOKEN_SECRET"]

# Slack configuration
slackurl = ENV["SLACK_WEBHOOK"]

# load tweetlist
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
      tweettime_now = (Time.now - 0).strftime('%m/%d %H:%M:%S')
      tweettime_nex = (Time.now + (60*60*24)).strftime('%m/%d %H:%M:%S')
      # tweet
      tweet = tweetlist.assoc(tweettime_now)
      if tweet then
        begin
          logging(create_tweet(create_tweet_url, consumer_key, consumer_secret, access_token, access_token_secret, tweet[1]))
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
