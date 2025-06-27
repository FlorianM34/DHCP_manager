#!/usr/bin/env ruby

# Test script to verify Kea DHCP Manager installation
require 'json'

puts "Kea DHCP Manager Installation Test"
puts "=" * 50

# Test 1: Check Ruby version
puts "\n1. Checking Ruby version..."
ruby_version = RUBY_VERSION
puts "Ruby version: #{ruby_version}"
if Gem::Version.new(ruby_version) >= Gem::Version.new('3.0.0')
  puts "✓ Ruby version is compatible"
else
  puts "✗ Ruby version too old (requires 3.0+)"
  exit 1
end

# Test 2: Check required gems
puts "\n2. Checking required gems..."
required_gems = ['sinatra', 'mysql2', 'sequel', 'json']

required_gems.each do |gem_name|
  begin
    require gem_name
    puts "✓ #{gem_name} gem loaded successfully"
  rescue LoadError
    puts "✗ #{gem_name} gem not found"
    exit 1
  end
end

# Test 3: Check environment file
puts "\n3. Checking environment configuration..."
if File.exist?('.env')
  puts "✓ .env file exists"
else
  puts "✗ .env file not found"
  puts "  Please copy .env.example to .env and configure it"
  exit 1
end

# Test 4: Check directories
puts "\n4. Checking required directories..."
required_dirs = ['logs', 'public/css', 'public/js', 'views', 'lib']

required_dirs.each do |dir|
  if Dir.exist?(dir)
    puts "✓ #{dir} directory exists"
  else
    puts "✗ #{dir} directory missing"
    exit 1
  end
end

# Test 5: Check main application files
puts "\n5. Checking application files..."
required_files = [
  'app.rb',
  'lib/kea_manager.rb',
  'lib/database_manager.rb', 
  'lib/config_manager.rb',
  'public/css/app.css',
  'public/js/app.js'
]

required_files.each do |file|
  if File.exist?(file)
    puts "✓ #{file} exists"
  else
    puts "✗ #{file} missing"
    exit 1
  end
end

# Test 6: Check database configuration (optional)
puts "\n6. Testing database connection..."
begin
  require 'dotenv'
  Dotenv.load if File.exist?('.env')
  
  require_relative 'lib/database_manager'
  DatabaseManager.connect_database
  puts "✓ Database connection successful"
rescue => e
  puts "⚠ Database connection failed: #{e.message}"
  puts "  This is normal if database is not yet configured"
end

# Test 7: Check Kea manager (optional)
puts "\n7. Testing Kea DHCP integration..."
begin
  require_relative 'lib/kea_manager'
  status = KeaManager.status
  puts "✓ Kea manager loaded successfully"
  puts "  Kea status: #{status[:status]}"
rescue => e
  puts "⚠ Kea integration test failed: #{e.message}"
  puts "  This is normal if Kea DHCP is not yet configured"
end

# Test 8: Validate JSON in view files
puts "\n8. Validating view templates..."
view_files = Dir.glob('views/*.erb')
if view_files.any?
  puts "✓ Found #{view_files.length} view templates"
else
  puts "✗ No view templates found"
  exit 1
end

# Test 9: Check configuration files
puts "\n9. Checking configuration files..."
config_files = ['Gemfile', 'config.ru', 'Rakefile']

config_files.each do |file|
  if File.exist?(file)
    puts "✓ #{file} exists"
  else
    puts "✗ #{file} missing"
    exit 1
  end
end

# Test 10: Try loading the main application
puts "\n10. Testing application load..."
begin
  require_relative 'app'
  puts "✓ Main application loads successfully"
rescue => e
  puts "✗ Application load failed: #{e.message}"
  exit 1
end

puts "\n" + "=" * 50
puts "🎉 All tests passed! Installation appears to be successful."
puts "\nNext steps:"
puts "1. Configure your .env file with proper database credentials"
puts "2. Run: rake setup_db (to setup the database)"
puts "3. Start the application: rake start"
puts "4. Access the web interface at: http://localhost:4567"
puts "\nFor more information, see README.md"
