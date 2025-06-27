# Changelog

All notable changes to the Kea DHCP Manager project will be documented in this file.

## [1.0.0] - 2025-06-27

### Added
- Initial release of Kea DHCP Manager
- Complete web-based interface for Kea DHCP server management
- Subnet management with add/delete functionality
- IP reservation management with MySQL database backend
- Real-time server status monitoring
- Active DHCP lease display
- Configuration management and validation
- Automatic configuration backup system
- Responsive Bootstrap-based UI
- Authentication and session management
- Comprehensive logging system
- RESTful API endpoints for AJAX operations
- Auto-refresh functionality for real-time updates

### Core Features
- **Dashboard**: Overview of server status, active leases, and system metrics
- **Subnet Management**: Add and delete DHCP subnets with validation
- **IP Reservations**: Reserve specific IP addresses for devices
- **Configuration**: Validate, backup, and reload Kea configurations
- **Monitoring**: Real-time status updates and lease tracking
- **Security**: Secure authentication and input validation

### Technical Components
- Ruby/Sinatra web framework
- MySQL database integration via Sequel ORM
- Bootstrap 5 responsive design
- RESTful API architecture
- Modular Ruby class structure
- Comprehensive error handling
- Automated testing capabilities

### Installation & Deployment
- Automated setup script for Debian-based systems
- Systemd service configuration
- Nginx reverse proxy support
- Docker deployment option
- Comprehensive documentation

### Documentation
- Complete README with installation instructions
- API documentation
- Configuration examples
- Troubleshooting guide
- Security recommendations

---

**Author**: MiniMax Agent  
**License**: See LICENSE file for details
