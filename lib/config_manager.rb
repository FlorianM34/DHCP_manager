require 'json'
require 'fileutils'
require 'logger'

class ConfigManager
  class << self
    def logger
      @logger ||= Logger.new('logs/config.log')
    end

    def config_path
      ENV['KEA_CONFIG_PATH'] || '/etc/kea/kea-dhcp4.conf'
    end

    def backup_path
      "#{File.dirname(config_path)}/backups"
    end

    # Load current Kea configuration
    def load_config
      begin
        if File.exist?(config_path)
          content = File.read(config_path)
          JSON.parse(content)
        else
          logger.warn("Configuration file not found: #{config_path}")
          generate_default_config
        end
      rescue JSON::ParserError => e
        logger.error("Invalid JSON in config file: #{e.message}")
        nil
      rescue => e
        logger.error("Failed to load configuration: #{e.message}")
        nil
      end
    end

    # Save configuration to file
    def save_config(config)
      begin
        # Create backup first
        create_backup
        
        # Validate configuration before saving
        unless validate_config_structure(config)
          return { success: false, error: 'Invalid configuration structure' }
        end
        
        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(config_path))
        
        # Write configuration
        File.write(config_path, JSON.pretty_generate(config))
        
        logger.info("Configuration saved to #{config_path}")
        { success: true }
      rescue => e
        logger.error("Failed to save configuration: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Validate current configuration
    def validate_config
      begin
        config = load_config
        return false unless config
        
        validate_config_structure(config)
      rescue => e
        logger.error("Configuration validation failed: #{e.message}")
        false
      end
    end

    # Create backup of current configuration
    def create_backup
      begin
        return unless File.exist?(config_path)
        
        FileUtils.mkdir_p(backup_path)
        
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        backup_file = File.join(backup_path, "kea-dhcp4_#{timestamp}.conf")
        
        FileUtils.cp(config_path, backup_file)
        
        # Keep only last 10 backups
        cleanup_old_backups
        
        logger.info("Configuration backed up to #{backup_file}")
        backup_file
      rescue => e
        logger.error("Failed to create backup: #{e.message}")
        nil
      end
    end

    # Update configuration with database reservations
    def update_config_with_reservations
      begin
        config = load_config
        return { success: false, error: 'Failed to load configuration' } unless config
        
        # Get reservations from database
        reservations = DatabaseManager.generate_kea_reservations_config
        
        # Update each subnet with its reservations
        subnets = config.dig('Dhcp4', 'subnet4') || []
        
        subnets.each do |subnet|
          subnet_id = subnet['id']
          subnet_reservations = reservations.select { |r| r['subnet-id'] == subnet_id }
          subnet['reservations'] = subnet_reservations
        end
        
        # Save updated configuration
        result = save_config(config)
        if result[:success]
          logger.info("Configuration updated with #{reservations.length} reservations")
        end
        
        result
      rescue => e
        logger.error("Failed to update configuration with reservations: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Get configuration statistics
    def get_config_stats
      begin
        config = load_config
        return {} unless config
        
        subnets = config.dig('Dhcp4', 'subnet4') || []
        total_reservations = subnets.sum { |subnet| (subnet['reservations'] || []).length }
        total_pools = subnets.sum { |subnet| (subnet['pools'] || []).length }
        
        {
          total_subnets: subnets.length,
          total_reservations: total_reservations,
          total_pools: total_pools,
          config_file_size: File.exist?(config_path) ? File.size(config_path) : 0,
          last_modified: File.exist?(config_path) ? File.mtime(config_path) : nil
        }
      rescue => e
        logger.error("Failed to get configuration stats: #{e.message}")
        {}
      end
    end

    # List available backups
    def list_backups
      begin
        return [] unless Dir.exist?(backup_path)
        
        Dir.glob(File.join(backup_path, 'kea-dhcp4_*.conf')).map do |file|
          {
            filename: File.basename(file),
            path: file,
            created_at: File.mtime(file),
            size: File.size(file)
          }
        end.sort_by { |backup| backup[:created_at] }.reverse
      rescue => e
        logger.error("Failed to list backups: #{e.message}")
        []
      end
    end

    # Restore from backup
    def restore_backup(backup_filename)
      begin
        backup_file = File.join(backup_path, backup_filename)
        return { success: false, error: 'Backup file not found' } unless File.exist?(backup_file)
        
        # Create backup of current config before restoring
        create_backup
        
        # Restore backup
        FileUtils.cp(backup_file, config_path)
        
        logger.info("Configuration restored from #{backup_filename}")
        { success: true }
      rescue => e
        logger.error("Failed to restore backup: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    # Generate default Kea configuration
    def generate_default_config
      {
        'Dhcp4' => {
          'valid-lifetime' => 4000,
          'renew-timer' => 1000,
          'rebind-timer' => 2000,
          'interfaces-config' => {
            'interfaces' => ['*']
          },
          'lease-database' => {
            'type' => 'memfile',
            'persist' => true,
            'name' => '/var/lib/kea/dhcp4.leases'
          },
          'control-socket' => {
            'socket-type' => 'unix',
            'socket-name' => '/tmp/kea4-ctrl-socket'
          },
          'subnet4' => [],
          'loggers' => [
            {
              'name' => 'kea-dhcp4',
              'output_options' => [
                {
                  'output' => '/var/log/kea/kea-dhcp4.log'
                }
              ],
              'severity' => 'INFO',
              'debuglevel' => 0
            }
          ]
        }
      }
    end

    # Validate configuration structure
    def validate_config_structure(config)
      return false unless config.is_a?(Hash)
      return false unless config.key?('Dhcp4')
      
      dhcp4 = config['Dhcp4']
      return false unless dhcp4.is_a?(Hash)
      
      # Check required fields
      required_fields = ['valid-lifetime', 'interfaces-config']
      required_fields.all? { |field| dhcp4.key?(field) }
    end

    # Clean up old backups
    def cleanup_old_backups
      begin
        backups = list_backups
        return if backups.length <= 10
        
        old_backups = backups[10..-1]
        old_backups.each do |backup|
          File.delete(backup[:path])
          logger.info("Deleted old backup: #{backup[:filename]}")
        end
      rescue => e
        logger.error("Failed to cleanup old backups: #{e.message}")
      end
    end

    def format_file_size(bytes)
      return '0 B' if bytes == 0
      
      units = ['B', 'KB', 'MB', 'GB']
      unit_index = 0
      size = bytes.to_f
      
      while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
      end
      
      "#{size.round(1)} #{units[unit_index]}"
    end


    def format_uptime(seconds)
      return 'Unknown' unless seconds.is_a?(Numeric)
        
        days = seconds / 86400
        hours = (seconds % 86400) / 3600
        minutes = (seconds % 3600) / 60
        
        if days > 0
            "#{days.to_i}d #{hours.to_i}h #{minutes.to_i}m"
        elsif hours > 0
            "#{hours.to_i}h #{minutes.to_i}m"
        else
            "#{minutes.to_i}m"
        end
      end

    def log_level_color(level)
      case level.to_s.upcase
      when 'ERROR'
          'danger'
      when 'WARN'
          'warning'
      when 'INFO'
          'info'
      when 'DEBUG'
          'secondary'
      else
          'primary'
      end
    end
  end
end
