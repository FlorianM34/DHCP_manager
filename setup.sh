#!/bin/bash

# Kea DHCP Manager Setup Script
# This script automates the installation and configuration process

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Check if running on Debian/Ubuntu
check_os() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script is designed for Debian-based systems"
        exit 1
    fi
    log_success "Debian-based system detected"
}

# Check if MySQL is running
check_mysql() {
    if ! systemctl is-active --quiet mysql; then
        log_error "MySQL is not running. Please start MySQL service first."
        exit 1
    fi
    log_success "MySQL service is running"
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    sudo apt update
    
    # Install Ruby and development tools
    sudo apt install -y ruby ruby-dev build-essential git curl
    
    # Install MySQL client
    sudo apt install -y mysql-client
    
    # Install Kea DHCP (if not already installed)
    if ! command -v kea-dhcp4 &> /dev/null; then
        log "Installing Kea DHCP server..."
        sudo apt install -y kea-dhcp4-server kea-ctrl-agent
    else
        log_success "Kea DHCP already installed"
    fi
    
    # Install Bundler
    if ! command -v bundle &> /dev/null; then
        sudo gem install bundler
        log_success "Bundler installed"
    else
        log_success "Bundler already installed"
    fi
}

# Install Ruby dependencies
install_ruby_deps() {
    log "Installing Ruby dependencies..."
    
    if [[ ! -f Gemfile ]]; then
        log_error "Gemfile not found. Make sure you're in the correct directory."
        exit 1
    fi
    
    bundle install
    log_success "Ruby dependencies installed"
}

# Setup directories
setup_directories() {
    log "Creating necessary directories..."
    
    directories=("logs" "config/backups")
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        else
            log_success "Directory already exists: $dir"
        fi
    done
}

# Setup environment file
setup_env() {
    if [[ ! -f .env ]]; then
        log "Setting up environment configuration..."
        cp .env.example .env
        
        # Generate random session secret
        session_secret=$(openssl rand -hex 32)
        sed -i "s/change_this_in_production/$session_secret/" .env
        
        log_success "Environment file created"
        log_warning "Please edit .env file with your specific configuration"
    else
        log_success "Environment file already exists"
    fi
}

# Setup database
setup_database() {
    log "Setting up database..."
    
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Please run setup_env first."
        exit 1
    fi
    
    # Source environment variables
    source .env
    
    echo "Please enter your MySQL root password to setup the database:"
    mysql -u root -p < db/setup.sql
    
    log_success "Database setup completed"
}

# Configure Kea DHCP
configure_kea() {
    log "Configuring Kea DHCP..."
    
    kea_config="/etc/kea/kea-dhcp4.conf"
    
    if [[ ! -f "$kea_config" ]]; then
        log_warning "Kea configuration file not found at $kea_config"
        log "Creating minimal Kea configuration..."
        
        sudo tee "$kea_config" > /dev/null << 'EOF'
{
    "Dhcp4": {
        "valid-lifetime": 4000,
        "renew-timer": 1000,
        "rebind-timer": 2000,
        "interfaces-config": {
            "interfaces": ["*"]
        },
        "lease-database": {
            "type": "memfile",
            "persist": true,
            "name": "/var/lib/kea/dhcp4.leases"
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/tmp/kea4-ctrl-socket"
        },
        "subnet4": [],
        "loggers": [
            {
                "name": "kea-dhcp4",
                "output_options": [
                    {
                        "output": "/var/log/kea/kea-dhcp4.log"
                    }
                ],
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }
}
EOF
        log_success "Minimal Kea configuration created"
    else
        log_success "Kea configuration file exists"
    fi
    
    # Ensure control socket is configured
    if ! grep -q "control-socket" "$kea_config"; then
        log_warning "Control socket not found in Kea configuration"
        log "Please add control socket configuration to $kea_config"
    fi
}

# Setup systemd service
setup_service() {
    log "Setting up systemd service..."
    
    current_dir=$(pwd)
    
    sudo tee /etc/systemd/system/kea-dhcp-manager.service > /dev/null << EOF
[Unit]
Description=Kea DHCP Manager
After=network.target mysql.service kea-dhcp4-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$current_dir
Environment=RACK_ENV=production
ExecStart=/usr/local/bin/bundle exec rackup -p 4567 -o 0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    log_success "Systemd service created"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Test database connection
    if bundle exec ruby -e "require_relative 'lib/database_manager'; DatabaseManager.connect_database; puts 'Database OK'"; then
        log_success "Database connection test passed"
    else
        log_error "Database connection test failed"
        return 1
    fi
    
    # Test Kea connection
    if bundle exec ruby -e "require_relative 'lib/kea_manager'; status = KeaManager.status; puts 'Kea status: #{status[:status]}'"; then
        log_success "Kea connection test passed"
    else
        log_warning "Kea connection test failed - this is normal if Kea is not running"
    fi
    
    log_success "Installation tests completed"
}

# Main installation function
main() {
    echo "========================================"
    echo "    Kea DHCP Manager Setup Script"
    echo "========================================"
    echo
    
    check_root
    check_os
    
    log "Starting installation process..."
    
    # Install dependencies
    install_system_deps
    install_ruby_deps
    
    # Setup application
    setup_directories
    setup_env
    
    # Check MySQL before database setup
    if systemctl is-active --quiet mysql; then
        setup_database
    else
        log_warning "MySQL is not running. Please start MySQL and run: rake setup_db"
    fi
    
    # Configure services
    configure_kea
    
    # Ask if user wants to setup systemd service
    read -p "Do you want to setup systemd service? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_service
    fi
    
    # Test installation
    test_installation
    
    echo
    log_success "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Edit .env file with your configuration"
    echo "2. Start the application: rake start"
    echo "3. Access the web interface at: http://localhost:4567"
    echo
    echo "For more information, see README.md"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
