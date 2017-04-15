#!/usr/bin/env ruby -Ku

### 特定のtwitterアカウントのfollowerを取得するスクリプト

### Usage:
## 同じディレクトリに、API_key, API_secret, access_token, access_secretを
## 4行で記載したファイルをおいておくこと
## 第1引数にそのファイル名を指定(指定なきときは token.conf)
## 第2引数には情報取得対象としたいtwitterアカウント(screen_name)の書いてあるファイルを入れる
## 綴りの間違いがあると落ちるので注意(そこの例外処理はしていない)

## reference sites
# https://dev.twitter.com/docs/api/1.1/get/friends/list
# http://ameblo.jp/mizunosei/entry-10806493421.html
# https://gist.github.com/tsupo/5597066
# http://d.hatena.ne.jp/riocampos+tech/20140127/p2
# http://opentechnica.blogspot.jp/2013/01/rubytwitter-gemratelimitstatus.html
# http://www.minituku.net/courses/566428009/lessons/673214309/texts/854260098?locale=ja
# http://www.namaraii.com/rubytips/?%E6%97%A5%E4%BB%98%E3%81%A8%E6%99%82%E5%88%BB
# https://dev.twitter.com/docs/api/1.1/get/application/rate_limit_status
# https://github.com/sferik/twitter/issues/517
# http://d.hatena.ne.jp/riocampos+tech/20140127/p1

### Script:

## loading libraries
require 'rubygems'
require 'twitter'
require 'pp'

## loading user setting
# access token
if ARGV[0] == nil then
  conf_name = 'followers_rr.conf'
else
  conf_name = ARGV[0] 
end

# target screen_name list
if ARGV[1] == nil then
  target_name = 'followers_rr.accounts.conf'
else
  target_name = ARGV[1] 
end
target_accounts = Array.new()
open(target_name,'r') do |file|
  file.each_line do |line|
    target_accounts += [line.chomp.split(/\t/)]    
  end
end

# output_data
if ARGV[2] == nil then
  output_name = 'followers_log/tw_return_rate_'+(Time.now - 86400).strftime('%Y%m%d')
else
  output_name = ARGV[2] 
end

# define logging script activity function
def logging( log_str )
  begin
    file = open(File.expand_path('../_log_followers',__FILE__),'a')
    file.print Time.now.to_s, "\t", log_str, "\n"
  #STDOUT.sync = true
  #print Time.now.to_s, "\t", log_str, "\n"
  #STDOUT.sync = false
  ensure
    file.close
  end
end

## Initialize
# Twitter gem configuration
client = Twitter::REST::Client.new do |config|
  conf = open(File.expand_path('../'+conf_name,__FILE__),'r')
  config.consumer_key        = conf.gets.chomp
  config.consumer_secret     = conf.gets.chomp
  config.access_token        = conf.gets.chomp
  config.access_token_secret = conf.gets.chomp
  conf.close
end


# logging script activity (boot)
logging( "Log_Boot_twitter_followers_rr" )

# prepare variables
rate_limit = Hash.new()
follower_ids = Array.new()

## Main routine
# get follower's list loop
target_accounts.each { | target_account |

  ## clear followers list
  follower_ids.clear

  ## logging
  logging( "Start getting #{target_account[0]} 's follower_ids" )


  ## block for catch exception
  begin
    ## get follower list
    
    ids_loop = 1
    cursor = -1
    begin
      begin
        response = Twitter::REST::Request.new(client, :get, "https://api.twitter.com/1.1/followers/ids.json?screen_name=#{target_account[0]}&cursor=#{cursor}").perform
        ## catch exception ... rate_limit_over
      rescue Twitter::Error::TooManyRequests => error
        ## logging
        logging ( "Exception catch at get follower_ids : Exception type ( #{error} ) ... waiting until #{error.rate_limit.reset_at.to_s}" )
        ## wait rate_limit_reset
        sleep error.rate_limit.reset_in
        ## retry
        retry
        ## catch exception other
#      rescue
        ## logging
#        logging ( "Exception catch ( #{$!} )" )
#        retry
      end
      follower_ids = response[:ids]
      cursor = response[:next_cursor]
      logging ( "getting #{target_account[0]}'s follower_ids # #{ids_loop} , get #{response[:ids].size} ids " )
      ids_loop = ids_loop + 1

      ## record limit_rate
      begin
        rate_limit.clear
        rate_limit = Twitter::REST::Request.new(client, :get, 'https://api.twitter.com/1.1/application/rate_limit_status.json').perform
        logging ( "Start getting follower_ids ( #{follower_ids.size} ) \trate_limit_status.remaining\t#{rate_limit[:resources][:followers][:"/followers/ids"][:remaining]}" )
        ## catch exception ... rate_limit_over
      rescue Twitter::Error::TooManyRequests => error
        ## logging
        logging ( "Exception catch catch at get rate_limit : Exception type ( #{error} ) ... waiting until #{error.rate_limit.reset_at.to_s}")
        ## wait rate_limit_reset
        sleep error.rate_limit.reset_in
        ## retry
        retry
        ## catch exception other
#      rescue
        ## logging
#        logging ( "Exception catch ( #{$!} )" )
#        retry
      end

      ## count follower's number
      loop_count = (follower_ids.size - 1) / 100 + 1

      ## get follower's status (loop)
      loop_count.times do
    
        ## logging
        rate_limit.clear
        begin
          rate_limit = Twitter::REST::Request.new(client, :get, 'https://api.twitter.com/1.1/application/rate_limit_status.json').perform
          logging( "Start getting user_data ( #{((follower_ids.size - 1) / 100 + 1)} / #{loop_count} )\trate_limit_status.remaining\t#{rate_limit[:resources][:users][:"/users/lookup"][:remaining]}" )
          ## catch exception ... rate_limit_over
        rescue Twitter::Error::TooManyRequests => error
          ## logging
          logging ( "Exception catch catch at get rate_limit : Exception type ( #{error} ) ... waiting until #{error.rate_limit.reset_at.to_s}")
          ## wait rate_limit_reset
          sleep error.rate_limit.reset_in
          ## retry
          retry
          ## catch exception other
#        rescue
          ## logging
#          logging ( "Exception catch ( #{$!} )" )
#          retry
        end
        
        ## get follower's status by 100uu
        ids_temp = follower_ids.pop(100)
        begin
          accounts_temp = client.users(ids_temp)
          ## catch exception ... rate_limit_over
        rescue Twitter::Error::TooManyRequests => error
          ## logging
          logging ( "Exception catch catch at get followers' data : Exception type ( #{error} ) ... waiting until #{error.rate_limit.reset_at.to_s}")
        
          ## wait rate_limit_reset
          sleep error.rate_limit.reset_in
          ## retry
          retry
          ## catch exception other
#        rescue
          ## logging
#          logging ( "Exception catch ( #{$!} )" )
#          retry
        end
        
        ## write follower's status
        accounts_temp.each { | follower |
          begin
            file = open(File.expand_path('../'+output_name,__FILE__), 'a')
            file.print Time.now.to_s, "\t", (Time.now - 86400).strftime("%Y-%m-%d"), "\t", target_account[0], "\t" ,  follower.id, "\t", follower.screen_name, "\t", follower.followers_count, "\t", follower.statuses_count, "\n"
          ensure
            file.close
          end
        }
      end
      
    end while cursor > 0

    ## logging ( loop end )
    begin
      rate_limit = Twitter::REST::Request.new(client, :get, 'https://api.twitter.com/1.1/application/rate_limit_status.json').perform
      
      logging ("Finished getting #{target_account[0]}'s follower_ids")
      logging ("Twitter rate_limit (followers/ids) \t#{rate_limit[:resources][:followers][:"/followers/ids"][:remaining]}\t#{Time.at(rate_limit[:resources][:followers][:"/followers/ids"][:reset]).to_s}" )
      logging ("Twitter rate_limit (users/lookup) \t#{rate_limit[:resources][:users][:"/users/lookup"][:remaining]}\t#{Time.at(rate_limit[:resources][:users][:"/users/lookup"][:reset]).to_s}" )
      logging ("Twitter rate_limit (application/rate_limit_status) \t#{rate_limit[:resources][:application][:"/application/rate_limit_status"][:remaining]}\t#{Time.at(rate_limit[:resources][:application][:"/application/rate_limit_status"][:reset]).to_s}" )
      ## catch exception ... rate_limit_over
    rescue Twitter::Error::TooManyRequests => error
      ## logging
      logging ( "Exception catch catch at get rate_limit : Exception type ( #{error} ) ... waiting until #{error.rate_limit.reset_at.to_s}")
      ## wait rate_limit_reset
      sleep error.rate_limit.reset_in
      ## retry
      retry
      ## catch exception other
#    rescue
      ## logging
#      logging ( "Exception catch ( #{$!} )" )
#      retry
    end
    
    ## catch exception other
#  rescue
    
    ## logging
#    logging ( "Exception catch ( #{$!} )" )
#    retry
  end
}
