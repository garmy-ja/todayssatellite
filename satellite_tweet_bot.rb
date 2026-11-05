#!/usr/bin/env ruby -Ku
# frozen_string_literal: true

require 'rubygems'
require 'time'
require 'roo'
require 'net/http'
require 'uri'
require 'json'
require 'oauth'
require 'typhoeus'
require 'oauth/request_proxy/typhoeus_request'
require 'dotenv/load'

# The bot scripts live one directory below the repository's data/config files.
# Keep the same ../ layout used by the original script.
APP_ROOT = File.expand_path('.', __dir__)
LOG_FILE = File.join(APP_ROOT, '_log_tweets')
ENV_FILE = File.join(APP_ROOT, '.env')
TWEETLIST_FILE = File.join(APP_ROOT, 'tweetlist.xlsx')
X_CREATE_POST_URL = 'https://api.x.com/2/tweets'

# Log to both the log file and stdout. Logging failures must not hide the
# original error or take down the posting loop.
def logging(message, level: 'INFO')
  line = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}\t[#{level}]\t#{message}"

  begin
    File.open(LOG_FILE, 'a:UTF-8') { |file| file.puts(line) }
  rescue StandardError => e
    warn "#{Time.now} [ERROR] Could not write #{LOG_FILE}: #{e.class}: #{e.message}"
  end

  begin
    $stdout.sync = true
    puts(line)
  rescue StandardError => e
    warn "#{Time.now} [ERROR] Could not write to stdout: #{e.class}: #{e.message}"
  end
end

def log_exception(context, error)
  logging("#{context}: #{error.class}: #{error.message}", level: 'ERROR')
  Array(error.backtrace).first(15).each do |line|
    logging("  #{line}", level: 'ERROR')
  end
end

# Slack/Mattermost post. Raise on non-2xx responses so that webhook failures
# are not incorrectly reported as successful.
def slackpost(raw_url, payload)
  raise ArgumentError, 'webhook URL is not configured' if raw_url.to_s.strip.empty?

  uri = URI.parse(raw_url)
  raise ArgumentError, 'webhook URL must use HTTPS' unless uri.scheme == 'https'

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 15
  http.write_timeout = 15 if http.respond_to?(:write_timeout=)

  request = Net::HTTP::Post.new(uri.request_uri)
  request['Content-Type'] = 'application/json'
  request.body = payload

  response = http.request(request)
  unless response.is_a?(Net::HTTPSuccess)
    response_body = response.body.to_s.each_char.take(1_000).join
    raise "webhook returned HTTP #{response.code} #{response.message}: #{response_body}"
  end

  response
end

# Create one post using OAuth 1.0a User Context. X continues to support this
# authentication method for requests made on behalf of the account that owns
# the app. The request body is JSON and is intentionally not part of the
# OAuth signature's form-encoded parameters.
def create_tweet(url, consumer_key, consumer_secret, access_token, access_token_secret, text)
  consumer = OAuth::Consumer.new(
    consumer_key,
    consumer_secret,
    site: 'https://api.x.com',
    debug_output: false
  )
  user_token = OAuth::AccessToken.new(consumer, access_token, access_token_secret)

  oauth_params = {
    consumer: consumer,
    token: user_token
  }

  request_options = {
    method: :post,
    headers: {
      'User-Agent' => 'todayssatellite-bot/2.0',
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    },
    body: JSON.generate(text: text.to_s),
    connecttimeout: 10_000,
    timeout: 30_000
  }
  request = Typhoeus::Request.new(url, request_options)

  oauth_helper = OAuth::Client::Helper.new(
    request,
    oauth_params.merge(request_uri: url)
  )
  request.options[:headers]['Authorization'] = oauth_helper.header

  request.run
end

# Return only diagnostic response headers; never log Authorization or tokens.
def diagnostic_headers(response)
  headers = response.headers || {}
  wanted = %w[
    date
    content-type
    retry-after
    x-request-id
    x-transaction-id
    x-rate-limit-limit
    x-rate-limit-remaining
    x-rate-limit-reset
  ]

  wanted.each_with_object({}) do |name, result|
    pair = headers.find { |key, _value| key.to_s.casecmp?(name) }
    result[name] = pair[1] if pair && !pair[1].to_s.empty?
  end
end

# Log the HTTP result and the X API response body. A 2xx response alone is not
# considered a successful post: the documented create-post response is 201
# and includes data.id.
def log_x_response(response, scheduled_time)
  status = response.code.to_i
  body = response.body.to_s
  parsed_body = begin
    JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  response_data = parsed_body['data'] if parsed_body.is_a?(Hash)
  post_id = response_data['id'] if response_data.is_a?(Hash)
  headers = diagnostic_headers(response)

  if status == 201 && !post_id.to_s.empty?
    logging(
      "X POST success: scheduled_at=#{scheduled_time.inspect} " \
      "http_status=#{status} post_id=#{post_id} headers=#{headers.inspect}"
    )
    return true
  end

  response_body = body.each_char.take(4_000).join
  logging(
    "X POST failed: scheduled_at=#{scheduled_time.inspect} " \
    "http_status=#{response.code.inspect} " \
    "return_code=#{response.return_code.inspect} " \
    "return_message=#{response.return_message.inspect} " \
    "timed_out=#{response.timed_out?} headers=#{headers.inspect} " \
    "response_body=#{response_body.inspect}",
    level: 'ERROR'
  )
  false
end

def load_tweet_list
  xlsx = Roo::Excelx.new(TWEETLIST_FILE)
  xlsx.default_sheet = 'todayssatellite'

  list = []
  last_row = xlsx.last_row.to_i
  1.upto(last_row) do |row|
    list << [xlsx.cell(row, 1), xlsx.cell(row, 2)]
  end
  list
ensure
  xlsx.close if defined?(xlsx) && xlsx && xlsx.respond_to?(:close)
end

def load_configuration
  Dotenv.load(ENV_FILE)

  credential_names = %w[
    CONSUMER_KEY
    CONSUMER_SECRET
    ACCESS_TOKEN
    ACCESS_TOKEN_SECRET
  ]
  missing = credential_names.select { |name| ENV[name].to_s.strip.empty? }
  unless missing.empty?
    raise "Missing X API credentials in environment: #{missing.join(', ')}"
  end

  {
    consumer_key: ENV.fetch('CONSUMER_KEY'),
    consumer_secret: ENV.fetch('CONSUMER_SECRET'),
    access_token: ENV.fetch('ACCESS_TOKEN'),
    access_token_secret: ENV.fetch('ACCESS_TOKEN_SECRET'),
    slack_url: ENV['SLACK_WEBHOOK'],
    mattermost_url: ENV['MATTERMOST_WEBHOOK']
  }
end

begin
  logging('Start: satellite_tweet_bot.rb started.')
  logging("Configuration file: #{File.file?(ENV_FILE) ? ENV_FILE : 'not found (using process environment)'}")
  logging("X API endpoint: #{X_CREATE_POST_URL}")

  config = load_configuration
  logging('X API credentials: all required environment variables are present (values omitted).')

  tweetlist = []
  tweetlist_mtime = nil

  # The original minute polling / exact timestamp matching is intentionally
  # retained. Only loading and posting diagnostics are changed here.
  loop do
    begin
      current_mtime = File.mtime(TWEETLIST_FILE)
      if tweetlist_mtime.nil? || tweetlist_mtime < current_mtime
        refreshed_list = load_tweet_list
        tweetlist = refreshed_list
        tweetlist_mtime = current_mtime
        logging("Success: tweet list reloaded. list_count=#{tweetlist.count} mtime=#{tweetlist_mtime}")
      end
    rescue StandardError => e
      log_exception('Tweet list reload failed', e)
    end

    # Tweet list checks every 60 seconds (60 x 1-second polling).
    loopcount = 0
    begin
      tweettime_now = (Time.now - 0).strftime('%m/%d %H:%M:%S')
      tweettime_nex = (Time.now + (60 * 60 * 24)).strftime('%m/%d %H:%M:%S')

      tweet = tweetlist.assoc(tweettime_now)
      if tweet
        begin
          post_text = tweet[1].to_s
          logging(
            "X POST attempt: scheduled_at=#{tweettime_now.inspect} " \
            "text_characters=#{post_text.length}"
          )
          response = create_tweet(
            X_CREATE_POST_URL,
            config[:consumer_key],
            config[:consumer_secret],
            config[:access_token],
            config[:access_token_secret],
            post_text
          )
          log_x_response(response, tweettime_now)
        rescue StandardError => e
          log_exception("X POST request raised an exception (scheduled_at=#{tweettime_now.inspect})", e)
        end
      end

      # Next-day tweet announcement (Slack / Mattermost).
      pretweet = tweetlist.assoc(tweettime_nex)
      if pretweet
        begin
          prepayload = {
            'attachments' => [
              {
                'mrkdwn' => true,
                'pretext' => '今日の人工衛星: 翌日ツイートの予告',
                'text' => "以下のツイートが24時間後になされます\n#{pretweet[1]}",
                'mrkdwn_in' => ['text'],
                'color' => 'good'
              }
            ]
          }.to_json

          slack_response = slackpost(config[:slack_url], prepayload)
          mattermost_response = slackpost(config[:mattermost_url], prepayload)
          logging(
            "Execute: webhook announcements sent. " \
            "slack_http_status=#{slack_response.code} " \
            "mattermost_http_status=#{mattermost_response.code}"
          )
        rescue StandardError => e
          log_exception("Webhook announcement failed (scheduled_at=#{tweettime_nex.inspect})", e)
        end
      end

      sleep(1)
      loopcount += 1
    end until loopcount >= 60
  end

ensure
  logging('Stop: satellite_tweet_bot.rb exiting.')
end

