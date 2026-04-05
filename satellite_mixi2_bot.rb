#!/usr/bin/env ruby -Ku

# load library
require 'rubygems'
require 'time'
require 'roo'
require 'net/http'
require 'uri'
require 'json'
require 'httpx'
require 'google/protobuf'
require 'dotenv/load'

# -------------------------------------------------------------------
# mixi2 API エンドポイント / サーバーアドレス定義
# Connect プロトコル（gRPC-Web 互換 / HTTPS）を使用するため、
# gRPC バイナリストリーム接続は不要。CreatePost を HTTPS POST で呼ぶ。
# -------------------------------------------------------------------
TOKEN_URL      = 'https://application-auth.mixi.social/oauth2/token'.freeze
API_BASE_URL   = 'https://application-api.mixi.social'.freeze
CREATE_POST_RPC = "#{API_BASE_URL}/social.mixi.application.service.application_api.v1.ApplicationService/CreatePost".freeze

# -------------------------------------------------------------------
# ログ出力
# -------------------------------------------------------------------
def logging(log_str)
  file = open(File.expand_path('../_log_mixi2', __FILE__), 'a')
  STDOUT.sync = true
  [file, STDOUT].each { |io| io.print Time.now.to_s, "\t", log_str, "\n" }
  STDOUT.sync = false
ensure
  file&.close
end

# -------------------------------------------------------------------
# OAuth2 Client Credentials フローでアクセストークンを取得する。
# mixi2 SDK（Go 版）と同等の処理を Ruby で実装。
# トークンは有効期限の 60 秒前まで再利用する。
# -------------------------------------------------------------------
class Mixi2Authenticator
  def initialize(client_id, client_secret)
    @client_id     = client_id
    @client_secret = client_secret
    @access_token  = nil
    @expires_at    = Time.at(0)
  end

  def access_token
    refresh! if Time.now >= @expires_at
    @access_token
  end

  private

  def refresh!
    uri  = URI.parse(TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.body = URI.encode_www_form(
      grant_type:    'client_credentials',
      client_id:     @client_id,
      client_secret: @client_secret
    )

    res  = http.request(req)
    body = JSON.parse(res.body)

    raise "Token fetch failed (#{res.code}): #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    @access_token = body['access_token']
    expires_in    = (body['expires_in'] || 3600).to_i
    @expires_at   = Time.now + expires_in - 60  # 60 秒前に更新
    logging("Info: access token refreshed. expires in #{expires_in}s")
  end
end

# -------------------------------------------------------------------
# Protobuf メッセージ定義（protoc / .proto ファイル不要）
# google-protobuf gem の Ruby DSL でインライン定義する。
# CreatePostRequest: field 1 = text (string)
# -------------------------------------------------------------------
Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message 'social.mixi.application.service.application_api.v1.CreatePostRequest' do
    optional :text, :string, 1
  end
end
 
CreatePostRequest = Google::Protobuf::DescriptorPool.generated_pool
  .lookup('social.mixi.application.service.application_api.v1.CreatePostRequest')
  .msgclass

# -------------------------------------------------------------------
# mixi2 へのポスト投稿
#
# レスポンスヘッダーの調査により、サーバーは Connect プロトコルではなく
# 素の gRPC プロトコルで動作していることが判明した:
#   content-type: application/grpc
#   grpc-message: invalid gRPC request content-type "application/proto"
#
# gRPC unary リクエストのフォーマット:
#   Content-Type: application/grpc+proto
#   ボディ: [圧縮フラグ 1byte (0x00)] [メッセージ長 4byte big-endian] [Protobuf バイナリ]
#
# gRPC レスポンスのステータスはレスポンスボディではなく
# トレーラーヘッダー (grpc-status / grpc-message) で返される。
# httpx はトレーラーを response.headers に統合して返す。
#
# net/http は Ruby 3.3 時点で HTTP/2 非対応のため、
# ALPN ネゴシエーションで HTTP/2 を自動選択する httpx gem を使用する。
#
# デバッグのため、送受信の詳細を毎回ログに出力する。
# -------------------------------------------------------------------
 
# gRPC の Length-Prefixed Message フレームを組み立てる。
# 圧縮なし (compression flag = 0x00) の 5 バイトヘッダーを Protobuf バイナリの先頭に付加する。
def grpc_encode(proto_bytes)
  [0x00, proto_bytes.bytesize].pack('CN') + proto_bytes
end
 
def create_post(auth, text)
  token      = auth.access_token
  proto_body = CreatePostRequest.encode(CreatePostRequest.new(text: text))
  req_body   = grpc_encode(proto_body)
 
  req_headers = {
    'Content-Type'  => 'application/grpc+proto',
    'Authorization' => "Bearer #{token}",
    'Te'            => 'trailers'   # gRPC はトレーラーを必要とする
  }
 
  logging("Debug: POST #{CREATE_POST_RPC}")
  logging("Debug: headers Content-Type=#{req_headers['Content-Type']} " \
          "Authorization=Bearer ...#{token[-8..]}")
  logging("Debug: proto hex=#{proto_body.unpack1('H*')} (#{proto_body.bytesize} bytes) " \
          "framed=#{req_body.unpack1('H*')} (#{req_body.bytesize} bytes)")
 
  response = HTTPX.post(
    CREATE_POST_RPC,
    headers: req_headers,
    body:    req_body
  )
 
  # レスポンスヘッダー（トレーラー含む）をログに出力する
  res_headers_str = response.headers.to_h.map { |k, v| "#{k}=#{v}" }.join(' ')
  logging("Debug: response status=#{response.status} headers=#{res_headers_str}")
 
  # gRPC のエラーはトレーラーヘッダー grpc-status で返される。
  # grpc-status=0 が成功、それ以外はエラー。
  grpc_status  = response.headers['grpc-status'].to_i
  grpc_message = response.headers['grpc-message'] || ''
  unless grpc_status == 0
    raise "CreatePost failed (HTTP #{response.status} / gRPC status #{grpc_status}): #{grpc_message}"
  end
 
  response.body.to_s
end


# -------------------------------------------------------------------
# メイン処理
# -------------------------------------------------------------------
logging('Start: satellite_post_bot.rb started.')

# 認証情報を .env から読み込む
logging('Opening credentials: .env')
Dotenv.load(File.expand_path('../.env', __FILE__))

client_id     = ENV['MIXI2_CLIENT_ID']
client_secret = ENV['MIXI2_CLIENT_SECRET']

auth = Mixi2Authenticator.new(client_id, client_secret)

# ツイートリストの初回ロード
fs           = File::Stat.new(File.expand_path('../tweetlist.xlsx', __FILE__))
tsvtimestamp = fs.mtime - 1
tweetlist    = []

begin
  loop do
    # xlsx が更新されていればリロード
    fs = File::Stat.new(File.expand_path('../tweetlist.xlsx', __FILE__))
    if tsvtimestamp < fs.mtime
      tsvtimestamp = fs.mtime
      tweetlist.clear

      xlsx = Roo::Excelx.new(File.expand_path('../tweetlist.xlsx', __FILE__))
      xlsx.default_sheet = 'todayssatellite'
      (1..xlsx.last_row).each do |row|
        tweetlist << [xlsx.cell(row, 1), xlsx.cell(row, 2)]
      end
      logging("Success: post list (re)loaded. list count is #{tweetlist.count}")
    end

    # 1 秒ごとに時刻チェック、60 秒分まとめてから xlsx 更新チェックに戻る
    loopcount = 0
    begin
      tweettime_now = (Time.now).strftime('%m/%d %H:%M:%S')
      tweettime_nex = (Time.now + 60 * 60 * 24).strftime('%m/%d %H:%M:%S')

      # 現在時刻に一致するポストがあれば投稿
      post = tweetlist.assoc(tweettime_now)
      if post
        begin
          result = create_post(auth, post[1])
          logging("Execute: CreatePost succeeded. post_id=#{result.dig('post', 'postId')}")
        rescue => e
          logging("Error: CreatePost failed. #{e.message}")
        end
      end

      sleep(1)
      loopcount += 1
    end until loopcount >= 60
  end
ensure
  logging('Error: Daemon down.')
  raise
end
