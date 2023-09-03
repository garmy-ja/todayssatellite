#!/usr/bin/env ruby -Ku

# for bluesky
# load library
require 'rubygems'
require 'time'
require 'roo'
require 'dotenv'

# need for atproto
require 'net/http'
require 'json'
require 'uri'
require 'date'

# define logging script activity function
def logging( log_str )
  begin
    file = open(File.expand_path('../_log_posts',__FILE__),'a')
    file.print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = true
  print Time.now.to_s, "\t", log_str, "\n"
  STDOUT.sync = false
  ensure
    file.close
  end
end

## functions for Bluesky
def atproto_login( id, pwd )
    uri = URI.parse('https://bsky.social/xrpc/com.atproto.server.createSession')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme === "https"

    headers = {'Content-Type': 'application/json; charset=UTF-8'}
    params = {identifier: id, password: pwd}

    response = http.post(uri.path, params.to_json, headers)

    return JSON.parse(response.body)['did'], JSON.parse(response.body)['accessJwt']
end

def atproto_getfeed( id, accessJwt )
    uri2 = URI.parse('https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed')
    params2 = {actor: id, limit: '1'}
    uri2.query = URI.encode_www_form(params2)

    http2 = Net::HTTP.new(uri2.host, uri2.port)
    http2.use_ssl = uri2.scheme === "https"

    req2 = Net::HTTP::Get.new uri2.request_uri
    req2['Content-Type']='application/json; charset=UTF-8'
    req2['Authorization']="Bearer #{accessJwt}"

    response2 = http2.request req2

    return response2.body
end

def atproto_postfeed( did, record, accessJwt )
    uri3 = URI.parse('https://bsky.social/xrpc/com.atproto.repo.createRecord')
    http3 = Net::HTTP.new(uri3.host, uri3.port)
    http3.use_ssl = uri3.scheme === "https"

    params3 = {
        "repo": did,
        "collection": 'app.bsky.feed.post',
        "record": record
        }

    headers3 = {'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': "Bearer #{accessJwt}"}

    response3 = http3.post(uri3.path, params3.to_json, headers3)

    return response3
end

def html_get_title( uri_text )
    uri = URI.parse(uri_text)
    response = Net::HTTP.get_response(uri)

    if response.body.match(/<title>(.+)<\/title>/m) then
      return response.body.match(/<title>(.+)<\/title>/m)[1]
    else
      return ""
    end
end

def get_url_positions( fulltext )
    pos_list = []
    start_pos = 0

    (1..(fulltext.scan(URI::DEFAULT_PARSER.make_regexp).size)).each{ |num|
      pos_list.push [
        fulltext.byteslice(
          fulltext.byteindex(URI::DEFAULT_PARSER.make_regexp,start_pos),
          fulltext.match(URI::DEFAULT_PARSER.make_regexp,start_pos).to_s.length
        ),[
          fulltext.byteindex(URI::DEFAULT_PARSER.make_regexp,start_pos),
          fulltext.byteindex(URI::DEFAULT_PARSER.make_regexp,start_pos)+fulltext.match(URI::DEFAULT_PARSER.make_regexp,start_pos).to_s.length
          ]
        ]
      start_pos = fulltext.index(URI::DEFAULT_PARSER.make_regexp,start_pos)+fulltext.match(URI::DEFAULT_PARSER.make_regexp,start_pos).to_s.length
    }

    return pos_list
end

def make_facets( pos_list )
    result = []

    pos_list.each { |pos|
      result.push({index: {
                "byteStart": pos[1][0],
                "byteEnd": pos[1][1]
            },
            features: [{
                "uri": pos[0],
                "$type": "app.bsky.richtext.facet#link"
            }]
        })
    }

    return result
end

def post_bluesky( tweettext )

    did, accessJwt = atproto_login(ENV["BLUESKY_ID"],ENV["BLUESKY_PW"])

    facetslist = get_url_positions( tweettext )

    nowtime = DateTime.now

    feedpost = {
        text: tweettext,
        createdAt: nowtime.rfc3339
    }

    if facetslist.size > 0 then
        feedpost[:facets] = make_facets( facetslist )
        feedpost[:embed] = {
            "$type": "app.bsky.embed.external" #,
#            "external": {
#                "uri": facetslist[0][0],
#                "title": html_get_title(facetslist[0][0]),
#                "description": ""
#            }
        }
    end

    return atproto_postfeed( did, feedpost, accessJwt )

end

## initialize

Dotenv.load(File.expand_path('../.env',__FILE__))

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
              logging(post_bluesky(tweet[1]))
              logging('Execute: Bluesky.update')
            rescue
              logging('Error: Bluesky.update')
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



