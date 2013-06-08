require "sinatra"
require "sinatra/reloader"

require './config/environments'
require 'haml'
require 'fileutils'

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  configure do
    enable :sessions
  end

  helpers do
    def kirjautunut?
      !session[:kayttaja].nil?
    end

    def kirjautunut_kayttaja
      DB.fetch("SELECT id, username FROM users WHERE id = ?", session[:kayttaja]).first
    end

    def pictures_visible_for_current_user
      DB[:pictures].where("Owner = ? or public = ?", session[:kayttaja], true)
    end
  end

  before do
    unless kirjautunut? or request.path_info =~ /^\/loginregister/ or request.path_info =~ /^\/login/ or request.path_info =~ /^\/register/
      redirect '/loginregister'
    end
  end

  get '/upload' do
    haml :upload
  end

  get '/view_images' do
    haml :view_images, :locals => {:images_to_be_listed => pictures_visible_for_current_user}
  end

  get '/view_images/:tags' do
    cats = DB[:categorizations]
    matches = pictures_visible_for_current_user
    params[:tags].split('+').each_with_index do |tag,i|
      if i==0
        cats = cats.where("category_name = ?", tag)
      else
        cats = cats.or("category_name = ?", tag)
      end
    end
    matching_ids = []
    cats.each do |cat|
      matching_ids.push(cat[:picture_id])
    end
    matches = matches.where("id in ?", matching_ids)
    haml :view_images, :locals => {:images_to_be_listed => matches}
  end

  get '/image/:user/:image' do
    content_type 'image/png'
    File.read("uploads/#{params[:user]}/#{params[:image]}")
  end

  get '/viewimage/:user/:image' do
    image = DB[:pictures].where("owner = ? and id = ?", params[:user], params[:image]).first
    haml :view_image, :locals => {:image => image}
  end

  get '/delete/:user/:image' do
    if DB[:pictures].where("Owner = ?", params[:image]).empty?
      return "Error: this is not your image"
    end
    DB[:comments].where("picture_id = ?", params[:image]).delete
    DB[:categorizations].where("picture_id = ?", params[:image]).delete
    DB[:pictures].where("id = ?", params[:image]).delete
    path = "uploads/#{session[:kayttaja]}/#{params[:image]}"
    if File.exist?path
      File.delete(path)
    end
    redirect '/view_images'
  end

  get '/loginregister' do
    haml :loginregister
  end

  get '/mainpage' do
    haml :mainpage
  end

  get '/' do
    haml :mainpage
  end

  post '/register' do
    username = params[:username]
    password = params[:password]
    if username.length < 3
      return "Error: username must be at least 3 letters long"
    end
    if password.length < 5
      return "Error: username must be at least 5 letters long"
    end
    users = DB[:users]
    if !DB[:users].where(:username => username).empty?
      return "error, username already exists"
    else
      users << {:username => username, :password => password}
      "Successfully added user " + username +  " <br>with password " + password
    end
  end

  get '/logout' do
    session[:kayttaja] = nil
    redirect '/loginregister'
  end

  post '/login' do
    user = DB[:users].where('username = ?', params[:username])
    p user
    if user.empty?
      return "Username not found!"
    end

    user = DB[:users].where('username = ? and password = ?', params[:username], params[:password])
    if user.empty?
      return "supplied password incorrect!"
    end

    session[:kayttaja] = user.first[:id]
    redirect '/mainpage'
  end

  post '/comment' do
    params[:comment]
    params[:targetid]
    DB[:comments] << {:commenter => session[:kayttaja], :text => params[:comment], :picture_id => params[:targetid]}
    redirect back
  end

  post '/addcategory' do
    if DB[:pictures].where("id = ? and owner = ?",params[:targetid],session[:kayttaja]).empty?
      return "This is not your image"
    end
    DB[:categorizations] << {:category_name => params[:category], :picture_id => params[:targetid]}
    redirect back
  end

  get '/listusers' do
    users = ""
    DB[:users].each do |user|
       users += "name: '#{user[:username]}' pass: '#{user[:password]}'<br>"
    end
    return users
  end

  post '/upload' do
    if params[:myfile].nil?
      return "No image selected"
    end
    if !params[:myfile][:type].include? "image"
      return "Not a valid image file"
    end
    public = false
    if params[:public] == "on"
      public = true
    end
    pictures = DB[:pictures]
    addedID = pictures.insert({:name => params[:name], :owner => session[:kayttaja], :public => public})
    path = "uploads/#{session[:kayttaja]}/#{addedID}"
    unless File.directory?(File.dirname(path))
      FileUtils.mkpath(File.dirname(path))
    end
    if File.exist?path
      File.delete(path)
    end
    File.open(path, 'w') do |f|
      f.write(params['myfile'][:tempfile].read)
    end
    redirect '/view_images'
  end

end

def initDB

  unless DB.table_exists?(:users)
    DB.create_table :users do
      primary_key :id
      String :username, :unique => true
      String :password
    end
  end

  unless DB.table_exists?(:pictures)
    DB.create_table :pictures do
      primary_key :id
      String :name
      foreign_key :owner, :users
      TrueClass :public, :default => true
    end
  end

  unless DB.table_exists?(:categorizations)
    DB.create_table :categorizations do
      primary_key :id
      String :category_name
      foreign_key :picture_id, :pictures
    end
  end

  unless DB.table_exists?(:comments)
    DB.create_table :comments do
      primary_key :id
      String :text
      foreign_key :commenter, :users
      foreign_key :picture_id, :pictures
    end
  end
end

