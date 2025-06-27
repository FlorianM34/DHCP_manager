require 'dotenv/load'

desc "Setup the database"
task :setup_db do
  puts "Setting up database..."
  
  # Check if MySQL is available
  unless system('which mysql > /dev/null 2>&1')
    puts "Error: MySQL client not found. Please install MySQL client."
    exit 1
  end
  
  # Run database setup script
  db_script = File.join(__dir__, 'db', 'setup.sql')
  
  puts "Running database setup script..."
  system("mysql -u root -p < #{db_script}")
  
  puts "Database setup completed!"
end

desc "Install dependencies"
task :install do
  puts "Installing Ruby dependencies..."
  system('bundle install')
  
  puts "Creating necessary directories..."
  %w[logs backups].each do |dir|
    Dir.mkdir(dir) unless Dir.exist?(dir)
    puts "Created directory: #{dir}"
  end
  
  puts "Dependencies installed successfully!"
end

desc "Start the application"
task :start do
  puts "Starting Kea DHCP Manager..."
  
  # Check if .env file exists
  unless File.exist?('.env')
    puts "Warning: .env file not found. Copying from .env.example..."
    system('cp .env.example .env')
    puts "Please edit .env file with your configuration before starting."
    exit 1
  end
  
  # Start with rackup
  system('bundle exec rackup -p 4567 -o 0.0.0.0')
end

desc "Start in development mode"
task :dev do
  ENV['RACK_ENV'] = 'development'
  puts "Starting in development mode..."
  system('bundle exec ruby app.rb')
end

desc "Run tests"
task :test do
  puts "Running tests..."
  system('bundle exec rspec')
end

desc "Create backup of Kea configuration"
task :backup_config do
  require_relative 'lib/config_manager'
  
  puts "Creating configuration backup..."
  backup_file = ConfigManager.create_backup
  
  if backup_file
    puts "Backup created: #{backup_file}"
  else
    puts "Failed to create backup"
    exit 1
  end
end

desc "Validate Kea configuration"
task :validate_config do
  require_relative 'lib/config_manager'
  
  puts "Validating Kea configuration..."
  if ConfigManager.validate_config
    puts "Configuration is valid"
  else
    puts "Configuration has errors"
    exit 1
  end
end

desc "Show application status"
task :status do
  require_relative 'lib/kea_manager'
  require_relative 'lib/database_manager'
  
  puts "Kea DHCP Manager Status"
  puts "=" * 40
  
  # Kea status
  kea_status = KeaManager.status
  puts "Kea DHCP Server: #{kea_status[:status]}"
  puts "PID: #{kea_status[:pid]}" if kea_status[:pid]
  puts "Uptime: #{kea_status[:uptime]}s" if kea_status[:uptime]
  
  # Database status
  begin
    reservations = DatabaseManager.list_reservations
    puts "Database: Connected"
    puts "IP Reservations: #{reservations.length}"
  rescue => e
    puts "Database: Error - #{e.message}"
  end
  
  # Configuration status
  config_valid = ConfigManager.validate_config
  puts "Configuration: #{config_valid ? 'Valid' : 'Invalid'}"
end

desc "Clean logs and temporary files"
task :clean do
  puts "Cleaning temporary files..."
  
  # Clean old log files
  Dir.glob('logs/*.log').each do |log_file|
    if File.mtime(log_file) < (Time.now - 7*24*60*60) # 7 days old
      File.delete(log_file)
      puts "Deleted old log: #{log_file}"
    end
  end
  
  # Clean old backups (keep last 10)
  backups = ConfigManager.list_backups rescue []
  if backups.length > 10
    backups[10..-1].each do |backup|
      File.delete(backup[:path])
      puts "Deleted old backup: #{backup[:filename]}"
    end
  end
  
  puts "Cleanup completed!"
end

desc "Generate SSL certificates for HTTPS"
task :ssl do
  puts "Generating SSL certificates..."
  
  ssl_dir = 'ssl'
  Dir.mkdir(ssl_dir) unless Dir.exist?(ssl_dir)
  
  # Generate private key
  system("openssl genrsa -out #{ssl_dir}/server.key 2048")
  
  # Generate certificate signing request
  system("openssl req -new -key #{ssl_dir}/server.key -out #{ssl_dir}/server.csr")
  
  # Generate self-signed certificate
  system("openssl x509 -req -days 365 -in #{ssl_dir}/server.csr -signkey #{ssl_dir}/server.key -out #{ssl_dir}/server.crt")
  
  puts "SSL certificates generated in ssl/ directory"
end

desc "Show help"
task :help do
  puts "Available tasks:"
  puts "  rake install        - Install dependencies and setup directories"
  puts "  rake setup_db       - Setup MySQL database"
  puts "  rake start          - Start the application in production mode"
  puts "  rake dev            - Start the application in development mode"
  puts "  rake test           - Run tests"
  puts "  rake backup_config  - Create backup of Kea configuration"
  puts "  rake validate_config - Validate Kea configuration"
  puts "  rake status         - Show application status"
  puts "  rake clean          - Clean logs and temporary files"
  puts "  rake ssl            - Generate SSL certificates"
  puts "  rake help           - Show this help"
end

# Default task
task default: :help
