require 'json'
require 'open3'
require 'httparty'
require 'logger'

class KeaManager
  class << self
    def logger
      @logger ||= Logger.new('logs/kea.log')
    end

    def config_path
      ENV['KEA_CONFIG_PATH'] || '/etc/kea/kea-dhcp4.conf'
    end

    def control_socket
      ENV['KEA_CONTROL_SOCKET'] || '/tmp/kea4-ctrl-socket'
    end

    def lease_file
      ENV['KEA_LEASE_FILE'] || '/var/lib/kea/dhcp4.leases'
    end

    # Check Kea DHCP server status
    def status
      begin
        result = send_command('status-get')
        if result[:success]
          {
            status: 'running',
            pid: result[:data]['pid'],
            uptime: result[:data]['uptime']
          }
        else
          { status: 'stopped', error: result[:error] }
        end
      rescue => e
        logger.error("Status check failed: #{e.message}")
        { status: 'unknown', error: e.message }
      end
    end

    # Get server uptime
    def uptime
      status_info = status
      status_info[:uptime] || 0
    end

    # List all configured subnets
    def list_subnets
      begin
        result = send_command('config-get')
        if result[:success]
          config = result[:data]
          subnets = config.dig('Dhcp4', 'subnet4') || []
          
          subnets.map do |subnet|
            {
              id: subnet['id'],
              subnet: subnet['subnet'],
              pools: subnet['pools'] || [],
              reservations: subnet['reservations'] || [],
              option_data: subnet['option-data'] || []
            }
          end
        else
          logger.error("Failed to list subnets: #{result[:error]}")
          []
        end
      rescue => e
        logger.error("List subnets failed: #{e.message}")
        []
      end
    end

    # Add a new subnet
    def add_subnet(subnet_data)
      begin
        # Get current configuration
        config_result = send_command('config-get')
        return { success: false, error: 'Failed to get current config' } unless config_result[:success]
        
        config = config_result[:data]
        subnets = config.dig('Dhcp4', 'subnet4') || []
        
        # Generate new subnet ID
        max_id = subnets.map { |s| s['id'] }.max || 0
        new_id = max_id + 1
        
        # Prepare new subnet
        new_subnet = {
          'id' => new_id,
          'subnet' => subnet_data[:subnet],
          'pools' => subnet_data[:pools] || []
        }
        
        # Add option data if provided
        if subnet_data[:option_data] && !subnet_data[:option_data].empty?
          new_subnet['option-data'] = subnet_data[:option_data]
        end
        
        # Add to configuration
        subnets << new_subnet
        config['Dhcp4']['subnet4'] = subnets
        
        # Apply configuration
        result = send_command('config-set', config)
        if result[:success]
          logger.info("Added subnet: #{subnet_data[:subnet]} with ID #{new_id}")
          { success: true, subnet_id: new_id }
        else
          { success: false, error: result[:error] }
        end
      rescue => e
        logger.error("Add subnet failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Delete a subnet
    def delete_subnet(subnet_id)
      begin
        # Get current configuration
        config_result = send_command('config-get')
        return { success: false, error: 'Failed to get current config' } unless config_result[:success]
        
        config = config_result[:data]
        subnets = config.dig('Dhcp4', 'subnet4') || []
        
        # Remove subnet
        original_count = subnets.length
        subnets.reject! { |subnet| subnet['id'] == subnet_id }
        
        if subnets.length == original_count
          return { success: false, error: 'Subnet not found' }
        end
        
        config['Dhcp4']['subnet4'] = subnets
        
        # Apply configuration
        result = send_command('config-set', config)
        if result[:success]
          logger.info("Deleted subnet ID: #{subnet_id}")
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue => e
        logger.error("Delete subnet failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Get active DHCP leases
    def active_leases
      begin
        if File.exist?(lease_file)
          leases = []
          File.readlines(lease_file).each do |line|
            next if line.strip.empty? || line.start_with?('#')
            
            begin
              lease_data = JSON.parse(line)
              if lease_data['valid_lft'] && lease_data['valid_lft'] > 0
                leases << {
                  ip_address: lease_data['ip-address'],
                  hw_address: lease_data['hw-address'],
                  hostname: lease_data['hostname'],
                  subnet_id: lease_data['subnet-id'],
                  valid_lifetime: lease_data['valid-lft'],
                  expire: lease_data['expire']
                }
              end
            rescue JSON::ParserError
              # Skip invalid JSON lines
              next
            end
          end
          leases
        else
          logger.warn("Lease file not found: #{lease_file}")
          []
        end
      rescue => e
        logger.error("Failed to read leases: #{e.message}")
        []
      end
    end

    # Reload Kea configuration
    def reload_config
      begin
        result = send_command('config-reload')
        if result[:success]
          logger.info("Configuration reloaded successfully")
          { success: true }
        else
          { success: false, error: result[:error] }
        end
      rescue => e
        logger.error("Config reload failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Get recent log entries
    def recent_logs(limit = 100)
      begin
        log_files = ['/var/log/kea/kea-dhcp4.log', 'logs/kea.log']
        logs = []
        
        log_files.each do |log_file|
          next unless File.exist?(log_file)
          
          File.readlines(log_file).last(limit).each do |line|
            logs << {
              timestamp: extract_timestamp(line),
              level: extract_log_level(line),
              message: line.strip
            }
          end
        end
        
        logs.sort_by { |log| log[:timestamp] }.reverse.first(limit)
      rescue => e
        logger.error("Failed to read logs: #{e.message}")
        []
      end
    end

    private

    # Send command to Kea control socket
    def send_command(command, arguments = nil)
      begin
        command_data = { 'command' => command }
        command_data['arguments'] = arguments if arguments
        
        if File.exist?(control_socket)
          # Use kea-shell if available
          if system('which kea-shell > /dev/null 2>&1')
            send_command_via_shell(command_data)
          else
            send_command_via_socket(command_data)
          end
        else
          { success: false, error: 'Kea control socket not found' }
        end
      rescue => e
        logger.error("Send command failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Send command using kea-shell
    def send_command_via_shell(command_data)
      begin
        json_command = command_data.to_json
        cmd = "echo '#{json_command}' | kea-shell"
        
        stdout, stderr, status = Open3.capture3(cmd)
        
        if status.success?
          response = JSON.parse(stdout)
          if response[0]['result'] == 0
            { success: true, data: response[0]['arguments'] }
          else
            { success: false, error: response[0]['text'] }
          end
        else
          { success: false, error: stderr }
        end
      rescue JSON::ParserError => e
        { success: false, error: "Invalid JSON response: #{e.message}" }
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Send command directly to socket (fallback)
    def send_command_via_socket(command_data)
      begin
        require 'socket'
        
        socket = UNIXSocket.new(control_socket)
        socket.write(command_data.to_json)
        socket.close_write
        
        response = socket.read
        socket.close
        
        parsed_response = JSON.parse(response)
        if parsed_response[0]['result'] == 0
          { success: true, data: parsed_response[0]['arguments'] }
        else
          { success: false, error: parsed_response[0]['text'] }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Extract timestamp from log line
    def extract_timestamp(line)
      # Try to match common timestamp formats
      timestamp_match = line.match(/(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})/)
      if timestamp_match
        begin
          Time.parse(timestamp_match[1])
        rescue
          Time.now
        end
      else
        Time.now
      end
    end

    # Extract log level from log line
    def extract_log_level(line)
      case line
      when /ERROR/i
        'ERROR'
      when /WARN/i
        'WARN'
      when /INFO/i
        'INFO'
      when /DEBUG/i
        'DEBUG'
      else
        'INFO'
      end
    end
  end
end
