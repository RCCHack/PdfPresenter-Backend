require 'yaml'
require 'twitter'
require 'redis'
require_relative 'src/user'

# 配信ルーム
class Room
  attr_reader :session_id, :room_id, :page

  @@redis = Redis.new

  # pdfを元に 
  # 初期生成データ，stream確立
  def initialize pdf, hash_tag
    # adminユーザとその他
    @admin = nil
    @users = []

    # ページ情報
    @page = 1
    @hash_tag = hash_tag

    # 内部生成でええやろ(適当)
    @session_id = SecureRandom.hex() 
    @room_id = (0...5).map{ ('A'..'Z').to_a[rand(26)] }.join

    # postされたpdfはredisに(keyがroom_id)
    @@redis.store_pdf(@@redis, @room_id)
    # stream立てる
    @stream = establish_stream @hash_tag
  end

  # redisから
  def get_pdf
    @@redis.get(@room_id)
  end

  # adminユーザ追加
  def add_admin admin
    return false unless admin.admin
    @admin = admin
    admin.room = self
  end

  # normalユーザ追加
  def add_user user
    users << user
    user.room = self
  end

  # pdfをredisにStore
  def store_pdf pdf

  end

  # page更新を反映・通知
  def update_page page
    @page = page
    # パンピーに送信
    @users.each do |u|
      u.send_page page
    end
  end

  # commentを送信
  def provide_comment comment
    # adminとパンピーに送信
    @add_user.send_comment comment
    @users.each do |u|
      u.send_comment comment
    end
  end

  # close処理
  def close_room
    # streamの入ったThread殺す
    Thread.kill @thread

    # 終了を通知
    @users.each do |u|
      u.send_finish()
    end

    $rooms.delete self
  end

  private

  # track stream生成
  def establish_stream hash_tag
    client = Twitter::Streaming::Client.new do |config|
      config.consumer_key = auth["consumer_key"]
      config.consumer_secret = auth["consumer_secret"]
      config.access_token = auth["access_token"]
      config.access_token_secret = auth["access_secret"]
    end

    @thread = Thread.new do
      client.filter(track: hash_tag) do |obj|
        next unless obj.is_a?(Twitter::Tweet)

        provide_comment(obj.text)
      end
    end
  end
end
