-- Kea DHCP Manager Database Setup Script
-- This script creates the necessary database and tables for the application

-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS `kea_dhcp` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create user and grant privileges
-- Replace 'your_secure_password' with a strong password
CREATE USER IF NOT EXISTS 'kea_user'@'localhost' IDENTIFIED BY 'your_secure_password';
GRANT ALL PRIVILEGES ON `kea_dhcp`.* TO 'kea_user'@'localhost';
FLUSH PRIVILEGES;

-- Use the database
USE `kea_dhcp`;

-- Create IP reservations table
CREATE TABLE IF NOT EXISTS `dhcp4_reservations` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `ip_address` varchar(15) NOT NULL,
    `hw_address` varchar(17) NOT NULL,
    `hostname` varchar(255) DEFAULT NULL,
    `subnet_id` int(11) NOT NULL,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_ip` (`ip_address`),
    UNIQUE KEY `unique_mac` (`hw_address`),
    KEY `idx_subnet_id` (`subnet_id`),
    KEY `idx_ip_address` (`ip_address`),
    KEY `idx_hw_address` (`hw_address`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create activity logs table
CREATE TABLE IF NOT EXISTS `dhcp4_logs` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `action` varchar(100) NOT NULL,
    `details` text,
    `user_ip` varchar(45) DEFAULT NULL,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_action` (`action`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create configuration backup tracking table
CREATE TABLE IF NOT EXISTS `config_backups` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `filename` varchar(255) NOT NULL,
    `file_path` varchar(500) NOT NULL,
    `file_size` bigint(20) DEFAULT NULL,
    `checksum` varchar(64) DEFAULT NULL,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_filename` (`filename`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert some sample data for testing (optional)
-- Uncomment the following lines if you want sample data

-- INSERT INTO `dhcp4_reservations` (`ip_address`, `hw_address`, `hostname`, `subnet_id`) VALUES
-- ('192.168.1.100', '00:11:22:33:44:55', 'server01', 1),
-- ('192.168.1.101', '00:11:22:33:44:56', 'workstation01', 1),
-- ('192.168.1.102', '00:11:22:33:44:57', 'printer01', 1);

-- Insert initial log entry
INSERT INTO `dhcp4_logs` (`action`, `details`) VALUES
('database_setup', 'Database tables created successfully');

-- Show table status
SHOW TABLES;

-- Display table structures
DESCRIBE `dhcp4_reservations`;
DESCRIBE `dhcp4_logs`;
DESCRIBE `config_backups`;

-- Show grants for the kea_user
SHOW GRANTS FOR 'kea_user'@'localhost';

SELECT 'Database setup completed successfully!' AS status;
