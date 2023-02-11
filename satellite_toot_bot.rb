#!/usr/bin/env ruby -Ku

# for mastodon fork
# load library
require 'rubygems'
require 'time'
require 'roo'
require 'mastodon'
require 'highline/import'
require 'oauth2'
require 'dotenv'
require 'net/http'
require 'json'

# define logging script activity function
def logging( log_str )
  begin
    file = open(File.expand_path('../_log_toots',__FILE__),'a')
    file.print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = true
  print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = false
  ensure
    file.close
  end
end

## Initialize
# Mastodon gem configuration

## 以下 http://qiita.com/fjustin/items/afe21c00dc50c23cd109 のコードほとんどそのまま頂いてます
DEFAULT_APP_NAME = "todays-satellite-bot"
DEFAULT_MASTODON_URL = 'https://activitypub.garmy.jp'
FULL_ACCESS_SCOPES = "read write follow"

Dotenv.load(File.expand_path('../.env',__FILE__))

##インスタンスとURLの確認
logging("checking instance and URL")
if !ENV["MASTODON_URL"]
  ENV["MASTODON_URL"] = ask("Instance URL: "){|q| q.default = DEFAULT_MASTODON_URL}
  File.open(".env","a+") do |f|
    f.write "MASTODON_URL = '#{ENV["MASTODON_URL"]}'\n"
  end
end

scopes = ENV["MASTODON_SCOPES"] || FULL_ACCESS_SCOPES
app_name = ENV["MASTODON_APP_NAME"] || DEFAULT_APP_NAME

##クライアントIDの確認
logging("checking client id")
if !ENV["MASTODON_CLIENT_ID"] || !ENV["MASTODON_CLIENT_SECRET"]
  client = Mastodon::REST::Client.new(base_url: ENV["MASTODON_URL"])
  app = client.create_app(app_name, "urn:ietf:wg:oauth:2.0:oob", scopes)
  ENV["MASTODON_CLIENT_ID"] = app.client_id
  ENV["MASTODON_CLIENT_SECRET"] = app.client_secret
  File.open(".env","a+") do |f|
    f.write "MASTODON_CLIENT_ID = '#{ENV["MASTODON_CLIENT_ID"]}'\n"
    f.write "MASTODON_CLIENT_SECRET = '#{ENV["MASTODON_CLIENT_SECRET"]}'\n"
  end
end

##アクセストークンの確認（アカウントとパスワード）
logging("loading/setting account id/pw")
if !ENV["MASTODON_ACCESS_TOKEN"]
  client = OAuth2::Client.new(ENV["MASTODON_CLIENT_ID"],ENV["MASTODON_CLIENT_SECRET"],site: ENV["MASTODON_URL"])
  login_id = ask("Your Account: ")
  password = ask("Your Password: ")
  token = client.password.get_token(login_id,password, scope: scopes)
  ENV["MASTODON_ACCESS_TOKEN"] = token.token
  File.open(".env","a+") do |f|
    f.write "MASTODON_ACCESS_TOKEN = '#{ENV["MASTODON_ACCESS_TOKEN"]}'\n"
  end
end

client = Mastodon::REST::Client.new(base_url: ENV["MASTODON_URL"],
                                    bearer_token: ENV["MASTODON_ACCESS_TOKEN"])

logging('Start: satellite_bot_tweet.rb started.')

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
      logging(' : Success: tweet list reloaded. list count is '+tweetlist.count.to_s)
    end

  # tweet list checks 3hour.(10800)
    loopcount = 0
    begin
      tweet = tweetlist.assoc(Time.now.strftime('%m/%d %H:%M:%S'))
      if tweet then
        begin
          response = Net::HTTP.post URI(ENV["MASTODON_URL"]+"/api/v1/statuses"),
            "status="+tweet[1],
            "Authorization" => "Bearer "+ENV["MASTODON_ACCESS_TOKEN"]
          logging('Execute: Mastodon.update')
        rescue
          logging('Error: Mastodon.update')
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
