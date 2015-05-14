# encoding: utf-8

#製作者 : Kazuyoshi Yamada , 2015
#YomiYomi Reader
require 'sinatra'
# require 'sinatra/reloader'
require 'rubygems'
require 'active_record'
require 'warden' #login,Auth
require 'bcrypt' #暗号化
require 'rss'
require 'open-uri'

set :environment, :production
#wardenで使用するSession有効化
enable :sessions


helpers do
  #Feedのエントリーを更新し新しい記事をＤＢに挿入
  #ログインしていない場合何も起きない
  def refreshEntry(feed)
    unless request.env["warden"].user.id == feed.id
    end
    #Parserでxmlから情報をParsing
    begin
      fds = RSS::Parser.parse(feed.url)
    rescue RSS::InvalidRSSError
      fds = RSS::Parser.parse(feed.url,false)
    end
    #DBにない記事の場合挿入する
    fds.items.each do |entry|
      unless(Entry.find_by(url: entry.link,feed_id: feed.id))
        Entry.create do |e|
          e.title = entry.title
          e.url = entry.link
          e.source = fds.channel.title
          e.summary = entry.description
          e.feed_id = feed.id
          e.user_id = request.env["warden"].user.id
          e.readed = false
          e.favorite = false
        end
     end
    end
  end


end

#セッションに使用するＵＳＥＲの定義

Warden::Manager.serialize_from_session do |id|
  User.find(id)
end
Warden::Manager.serialize_into_session do |user|
  user.id
end

#ログイン時の認証の定義
Warden::Strategies.add :login_test do

  # 認証に必要なデータが送信されているか検証
  def valid?
    params["email"] && params["password"]
  end

  # 認証
  def authenticate!
    user_auth = User.find_by email: params['email']
    if(!user_auth.nil? && user_auth.authenticate(params['password']))
      success!(user_auth)
    else
      # ユーザー名とパスワードのどちらかでも間違っていたら
      # ログイン失敗
      fail!("Could not log in")
    end
  end
end

# Warden の設定
use Warden::Manager do |manager|
  # 先述の定義を使用
  manager.default_strategies :login_test

  # 失敗時の処理
  manager.failure_app = Sinatra::Application
end



######MODEL SETTING######


#Dababase, Active Record Setting
ActiveRecord::Base.establish_connection(
  "adapter" => "sqlite3",
  "database" => "db/yomiyomiReader.db")

#ActiveRecordのモデル定義
class User < ActiveRecord::Base
  has_secure_password
  has_many :categories
  has_many :feeds
  attr_accessor :password, :password_confirmation

  def password=(val)
    if val.present?
      self.password_digest = BCrypt::Password.create(val)
    end
    @password = val
  end
end
class Category < ActiveRecord::Base
  has_many :feeds
  has_many :entries, through: :feeds
end
class Feed < ActiveRecord::Base
  belongs_to :category
  has_many :entries
end
class Entry < ActiveRecord::Base
  belongs_to :feed
end




####Routing####




####フィードディスプレイ 関連ページレンダーリング ####

#Top Page. 
get '/' do
  if request.env["warden"].user.nil?
    redirect '/login'
  else
    redirect '/all'
  end
end
#Userが購読している記事を更新し, /allへ
get '/refresh' do
    Feed.where(:user_id => request.env["warden"].user.id).each do |f|
      refreshEntry(f)
    end
    redirect back
end

#Userが購読している全てのfeedを表示
get '/all' do
  @entries = Entry.where(user_id: request.env["warden"].user.id)
  @categories = request.env["warden"].user.categories
  @feeds = Feed.where(user_id: request.env["warden"].user.id)
  @page_title = "All"
  @page = 'All'
  haml :entry
end

#購読している特定のFeedの記事を表示。
get '/feed/:id' do |fid|
  feed = Feed.find(fid)
  if(feed.user_id != request.env["warden"].user.id)
    redirect '/invalid_access'
  else
    @categories = request.env["warden"].user.categories
    @page_title = feed.name
    @page = 'Feed'
    @entries = feed.entries
  end

  haml :entry
end

get '/favorite' do 
  @entries = Entry.where(user_id: request.env["warden"].user.id).where(favorite: true)
  @page_title = "Favorited Entries"
  @page = "favorite"
  @categories = request.env["warden"].user.categories

  haml :entry
end


####CategoryとFeedの追加、削除、移動####


#Category 追加 => /all
post '/post_category' do
  Category.create do |category|
    category.name = params["category"]
    category.user_id = request.env["warden"].user.id
  end
  redirect back
end

#Feed 追加(更新も行う。) 
post '/post_feed' do
  begin
    parsed = RSS::Parser.parse(params["feed_url"])
  rescue RSS::InvalidRSSError
    parsed = RSS::Parser.parse(params["feed_url"],false)
  end

  f = Feed.create do |feed|
    feed.name = parsed.channel.title
    feed.url = params["feed_url"]
    feed.user_id = request.env["warden"].user.id
    feed.category_id = params['category_id'].to_i
  end
  refreshEntry(f)
  redirect back
end

#Category 削除
post '/remove_category' do
  category = Category.find(params['category_id'].to_i)
  category.feeds.each do|f|
    f.entries.each{|e| e.destroy;}
    f.destroy
  end
  category.destroy

  redirect back
end
#Feed 削除
post '/remove_feed' do
  feed = Feed.find(params['feed_id'].to_i)
  feed.entries.each{|e| e.destroy;}
  feed.destroy

  redirect back
end
#Feed 移動(他のカテゴリに)
post '/move_feed' do
  feed = Feed.find(params['feed_id'].to_i)
  
  feed.category = Category.find(params['category_id'].to_i)
  feed.save

  redirect back

end
#Favorite
get '/add_favorite/:id' do |eid|
  entry = Entry.find(eid)
  entry.favorite = !entry.favorite?
  entry.save

  redirect back
end




#無効なアクセス
get '/invalid_access' do
  haml :invalid_access
end
#製作情報
get '/about' do
  haml :about
end



## ==== デザインの統合性に支障あり。保留
#特定カテゴリに属している記事 -
# get '/category/:id' do |cat|
#   @categories = Category.all
#   @page_title = cat
#   @page = 'Category'
#   category = Category.find(cat).name
#   if category != nil 
#     category.each do |c|
#       if !c 
#         c.feeds.each do |feed|
#           @entries += feed.entries
#         end
#       end
#     end
#   end

#   haml :entry
# end



###### LOGIN 関連 #######




get "/login" do
  haml :login
end

post "/login" do
  request.env["warden"].authenticate!
  redirect "/"
end

get '/signup' do
  haml :signup
end
get 'dupemail' do
  haml :dupemail
end
get '/difpass' do
  haml :difpass
end


post "/signup" do
  if(User.find_by(email: params['email'])) then
    redirect '/dupemail'
  end
  if(params['password'] != ['password_confirmation']) then
    redirect '/difpass'
  end

  user = User.create do |u|
    u.name = params['name']
    u.email = params['email']
    u.password = params['password']
    u.password_confirmation = params['password_confirmation']
  end
  if user.errors.any?
    redirect '/signup'
  end
  initial_category = Category.create do|c|
    c.name = "Uncategorized"
    c.user_id = user.id
  end
  redirect '/login'

end

post "/unauthenticated" do
  redirect '/'
end

get "/logout" do
  request.env["warden"].logout
  redirect '/'
end