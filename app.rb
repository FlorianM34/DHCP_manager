require 'sinatra'
require 'sinatra/json'
require 'sinatra/reloader' if development?
require 'json'
require 'logger'
require 'dotenv/load'

# Load application modules
require_relative 'lib/kea_manager'
require_relative 'lib/database_manager'
require_relative 'lib/config_manager'

class KeaDhcpApp < Sinatra::Base
  configure do
    set :public_folder, 'public'
    set :views, 'views'
    enable :sessions
    set :session_secret, ENV['SESSION_SECRET'] || 'development_secret'
    
    # Setup logging
    log_file = File.open('logs/app.log', 'a+')
    log_file.sync = true
    use Rack::CommonLogger, log_file
    
    set :logger, Logger.new(log_file)
    settings.logger.level = Logger.const_get(ENV['LOG_LEVEL'] || 'INFO')
  end

  helpers do
    def authenticated?
      session[:authenticated]
    end

    def require_auth
      redirect '/login' unless authenticated?
    end

    def log_action(action, details = {})
      settings.logger.info("Action: #{action}, Details: #{details.to_json}")
    end

    def flash_message(type, message)
      session[:flash] = { type: type, message: message }
    end

    def get_flash
      flash = session[:flash]
      session[:flash] = nil
      flash
    end
  end

  before do
    @flash = get_flash
  end

  # Authentication routes
  get '/login' do
    erb :login, layout: false
  end

  post '/login' do
    username = params[:username]
    password = params[:password]
    
    if username == ENV['ADMIN_USERNAME'] && password == ENV['ADMIN_PASSWORD']
      session[:authenticated] = true
      flash_message('success', 'Successfully logged in')
      redirect '/'
    else
      flash_message('error', 'Invalid credentials')
      redirect '/login'
    end
  end

  get '/logout' do
    session[:authenticated] = false
    flash_message('info', 'Successfully logged out')
    redirect '/login'
  end

  # Main dashboard
  get '/' do
    require_auth
    
    begin
      @kea_status = KeaManager.status
      @active_leases = KeaManager.active_leases
      @subnets = KeaManager.list_subnets
      @reservations = DatabaseManager.list_reservations
      @recent_logs = KeaManager.recent_logs(50)
      
      erb :dashboard
    rescue => e
      settings.logger.error("Dashboard error: #{e.message}")
      flash_message('error', "Error loading dashboard: #{e.message}")
      erb :dashboard
    end
  end

  # Subnet management
  get '/subnets' do
    require_auth
    
    begin
      @subnets = KeaManager.list_subnets
      erb :subnets
    rescue => e
      settings.logger.error("Subnets list error: #{e.message}")
      flash_message('error', "Error loading subnets: #{e.message}")
      erb :subnets
    end
  end

  post '/subnets' do
    require_auth
    
    begin
      subnet_data = {
        subnet: params[:subnet],
        pools: [{ pool: params[:pool] }],
        option_data: []
      }
      
      # Add router option if provided
      if params[:router] && !params[:router].empty?
        subnet_data[:option_data] << {
          name: "routers",
          data: params[:router]
        }
      end
      
      # Add DNS servers if provided
      if params[:dns_servers] && !params[:dns_servers].empty?
        subnet_data[:option_data] << {
          name: "domain-name-servers", 
          data: params[:dns_servers]
        }
      end
      
      result = KeaManager.add_subnet(subnet_data)
      log_action('add_subnet', subnet_data)
      
      if result[:success]
        flash_message('success', 'Subnet added successfully')
      else
        flash_message('error', "Failed to add subnet: #{result[:error]}")
      end
      
    rescue => e
      settings.logger.error("Add subnet error: #{e.message}")
      flash_message('error', "Error adding subnet: #{e.message}")
    end
    
    redirect '/subnets'
  end

  delete '/subnets/:subnet_id' do
    require_auth
    
    begin
      result = KeaManager.delete_subnet(params[:subnet_id].to_i)
      log_action('delete_subnet', { subnet_id: params[:subnet_id] })
      
      if result[:success]
        flash_message('success', 'Subnet deleted successfully')
      else
        flash_message('error', "Failed to delete subnet: #{result[:error]}")
      end
      
    rescue => e
      settings.logger.error("Delete subnet error: #{e.message}")
      flash_message('error', "Error deleting subnet: #{e.message}")
    end
    
    redirect '/subnets'
  end

  # IP Reservations management
  get '/reservations' do
    require_auth
    
    begin
      @reservations = DatabaseManager.list_reservations
      @subnets = KeaManager.list_subnets
      erb :reservations
    rescue => e
      settings.logger.error("Reservations list error: #{e.message}")
      flash_message('error', "Error loading reservations: #{e.message}")
      erb :reservations
    end
  end

  post '/reservations' do
    require_auth
    
    begin
      reservation_data = {
        ip_address: params[:ip_address],
        hw_address: params[:hw_address],
        hostname: params[:hostname],
        subnet_id: params[:subnet_id].to_i
      }
      
      result = DatabaseManager.add_reservation(reservation_data)
      log_action('add_reservation', reservation_data)
      
      if result[:success]
        # Reload Kea configuration to apply changes
        KeaManager.reload_config
        flash_message('success', 'IP reservation added successfully')
      else
        flash_message('error', "Failed to add reservation: #{result[:error]}")
      end
      
    rescue => e
      settings.logger.error("Add reservation error: #{e.message}")
      flash_message('error', "Error adding reservation: #{e.message}")
    end
    
    redirect '/reservations'
  end

  delete '/reservations/:id' do
    require_auth
    
    begin
      result = DatabaseManager.delete_reservation(params[:id].to_i)
      log_action('delete_reservation', { id: params[:id] })
      
      if result[:success]
        # Reload Kea configuration to apply changes
        KeaManager.reload_config
        flash_message('success', 'IP reservation deleted successfully')
      else
        flash_message('error', "Failed to delete reservation: #{result[:error]}")
      end
      
    rescue => e
      settings.logger.error("Delete reservation error: #{e.message}")
      flash_message('error', "Error deleting reservation: #{e.message}")
    end
    
    redirect '/reservations'
  end

  # Configuration management
  get '/config' do
    require_auth
    
    begin
      @config = ConfigManager.load_config
      @config_valid = ConfigManager.validate_config
      erb :config
    rescue => e
      settings.logger.error("Config load error: #{e.message}")
      flash_message('error', "Error loading configuration: #{e.message}")
      erb :config
    end
  end

  post '/config/reload' do
    require_auth
    
    begin
      result = KeaManager.reload_config
      log_action('reload_config')
      
      if result[:success]
        flash_message('success', 'Kea configuration reloaded successfully')
      else
        flash_message('error', "Failed to reload configuration: #{result[:error]}")
      end
      
    rescue => e
      settings.logger.error("Config reload error: #{e.message}")
      flash_message('error', "Error reloading configuration: #{e.message}")
    end
    
    redirect '/config'
  end

  # API endpoints for AJAX requests
  get '/api/status' do
    require_auth
    content_type :json
    
    begin
      {
        kea_status: KeaManager.status,
        active_leases: KeaManager.active_leases.count,
        uptime: KeaManager.uptime
      }.to_json
    rescue => e
      settings.logger.error("API status error: #{e.message}")
      status 500
      { error: e.message }.to_json
    end
  end

  get '/api/leases' do
    require_auth
    content_type :json
    
    begin
      KeaManager.active_leases.to_json
    rescue => e
      settings.logger.error("API leases error: #{e.message}")
      status 500
      { error: e.message }.to_json
    end
  end

  # Error handling
  error 404 do
    erb :not_found
  end

  error 500 do
    settings.logger.error("500 error: #{env['sinatra.error'].message}")
    erb :error
  end

  run! if app_file == $0
end
