require 'sequel'
require 'mysql2'
require 'logger'

class DatabaseManager
  class << self
    def logger
      @logger ||= Logger.new('logs/database.log')
    end

    def db
      @db ||= connect_database
    end

    # Initialize database connection
    def connect_database
      begin
        database_url = "mysql2://#{ENV['DB_USER']}:#{ENV['DB_PASSWORD']}@#{ENV['DB_HOST']}:#{ENV['DB_PORT']}/#{ENV['DB_NAME']}"
        Sequel.connect(database_url, logger: logger)
      rescue => e
        logger.error("Database connection failed: #{e.message}")
        raise e
      end
    end

    # Initialize database tables
    def setup_database
      begin
        # Create reservations table if it doesn't exist
        unless db.table_exists?(:dhcp4_reservations)
          db.create_table :dhcp4_reservations do
            primary_key :id
            String :ip_address, null: false, unique: true
            String :hw_address, null: false
            String :hostname
            Integer :subnet_id, null: false
            DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
            DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
            
            index :ip_address
            index :hw_address
            index :subnet_id
          end
          logger.info("Created dhcp4_reservations table")
        end

        # Create logs table for tracking changes
        unless db.table_exists?(:dhcp4_logs)
          db.create_table :dhcp4_logs do
            primary_key :id
            String :action, null: false
            String :details, text: true
            String :user_ip
            DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
            
            index :action
            index :created_at
          end
          logger.info("Created dhcp4_logs table")
        end

        true
      rescue => e
        logger.error("Database setup failed: #{e.message}")
        false
      end
    end

    # List all IP reservations
    def list_reservations
      begin
        reservations = db[:dhcp4_reservations].order(:id).all
        reservations.map do |reservation|
          {
            id: reservation[:id],
            ip_address: reservation[:ip_address],
            hw_address: reservation[:hw_address],
            hostname: reservation[:hostname],
            subnet_id: reservation[:subnet_id],
            created_at: reservation[:created_at],
            updated_at: reservation[:updated_at]
          }
        end
      rescue => e
        logger.error("List reservations failed: #{e.message}")
        []
      end
    end

    # Add new IP reservation
    def add_reservation(reservation_data)
      begin
        db.transaction do
          # Check if IP or MAC address already exists
          existing_ip = db[:dhcp4_reservations].where(ip_address: reservation_data[:ip_address]).first
          existing_mac = db[:dhcp4_reservations].where(hw_address: reservation_data[:hw_address]).first
          
          if existing_ip
            return { success: false, error: "IP address #{reservation_data[:ip_address]} is already reserved" }
          end
          
          if existing_mac
            return { success: false, error: "MAC address #{reservation_data[:hw_address]} already has a reservation" }
          end
          
          # Validate IP address format
          unless valid_ip_address?(reservation_data[:ip_address])
            return { success: false, error: "Invalid IP address format" }
          end
          
          # Validate MAC address format
          unless valid_mac_address?(reservation_data[:hw_address])
            return { success: false, error: "Invalid MAC address format" }
          end
          
          # Insert reservation
          reservation_id = db[:dhcp4_reservations].insert(
            ip_address: reservation_data[:ip_address],
            hw_address: reservation_data[:hw_address].downcase,
            hostname: reservation_data[:hostname],
            subnet_id: reservation_data[:subnet_id],
            created_at: Time.now,
            updated_at: Time.now
          )
          
          # Log the action
          log_action('add_reservation', reservation_data.merge(id: reservation_id))
          
          logger.info("Added reservation: #{reservation_data[:ip_address]} -> #{reservation_data[:hw_address]}")
          { success: true, id: reservation_id }
        end
      rescue => e
        logger.error("Add reservation failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Update existing IP reservation
    def update_reservation(id, reservation_data)
      begin
        db.transaction do
          existing = db[:dhcp4_reservations].where(id: id).first
          return { success: false, error: 'Reservation not found' } unless existing
          
          # Check for conflicts (excluding current record)
          if reservation_data[:ip_address]
            conflict_ip = db[:dhcp4_reservations]
                           .where(ip_address: reservation_data[:ip_address])
                           .exclude(id: id)
                           .first
            if conflict_ip
              return { success: false, error: "IP address #{reservation_data[:ip_address]} is already reserved" }
            end
          end
          
          if reservation_data[:hw_address]
            conflict_mac = db[:dhcp4_reservations]
                            .where(hw_address: reservation_data[:hw_address])
                            .exclude(id: id)
                            .first
            if conflict_mac
              return { success: false, error: "MAC address #{reservation_data[:hw_address]} already has a reservation" }
            end
          end
          
          # Prepare update data
          update_data = { updated_at: Time.now }
          
          [:ip_address, :hw_address, :hostname, :subnet_id].each do |field|
            if reservation_data[field]
              if field == :ip_address && !valid_ip_address?(reservation_data[field])
                return { success: false, error: "Invalid IP address format" }
              end
              if field == :hw_address && !valid_mac_address?(reservation_data[field])
                return { success: false, error: "Invalid MAC address format" }
              end
              
              update_data[field] = field == :hw_address ? reservation_data[field].downcase : reservation_data[field]
            end
          end
          
          # Update reservation
          db[:dhcp4_reservations].where(id: id).update(update_data)
          
          # Log the action
          log_action('update_reservation', { id: id }.merge(update_data))
          
          logger.info("Updated reservation ID: #{id}")
          { success: true }
        end
      rescue => e
        logger.error("Update reservation failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Delete IP reservation
    def delete_reservation(id)
      begin
        db.transaction do
          existing = db[:dhcp4_reservations].where(id: id).first
          return { success: false, error: 'Reservation not found' } unless existing
          
          db[:dhcp4_reservations].where(id: id).delete
          
          # Log the action
          log_action('delete_reservation', existing)
          
          logger.info("Deleted reservation ID: #{id} (#{existing[:ip_address]})")
          { success: true }
        end
      rescue => e
        logger.error("Delete reservation failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    # Get reservation by ID
    def get_reservation(id)
      begin
        reservation = db[:dhcp4_reservations].where(id: id).first
        return nil unless reservation
        
        {
          id: reservation[:id],
          ip_address: reservation[:ip_address],
          hw_address: reservation[:hw_address],
          hostname: reservation[:hostname],
          subnet_id: reservation[:subnet_id],
          created_at: reservation[:created_at],
          updated_at: reservation[:updated_at]
        }
      rescue => e
        logger.error("Get reservation failed: #{e.message}")
        nil
      end
    end

    # Get reservations for specific subnet
    def get_reservations_by_subnet(subnet_id)
      begin
        reservations = db[:dhcp4_reservations].where(subnet_id: subnet_id).order(:ip_address).all
        reservations.map do |reservation|
          {
            id: reservation[:id],
            ip_address: reservation[:ip_address],
            hw_address: reservation[:hw_address],
            hostname: reservation[:hostname],
            subnet_id: reservation[:subnet_id],
            created_at: reservation[:created_at],
            updated_at: reservation[:updated_at]
          }
        end
      rescue => e
        logger.error("Get reservations by subnet failed: #{e.message}")
        []
      end
    end

    # Generate Kea-compatible reservations configuration
    def generate_kea_reservations_config
      begin
        reservations = list_reservations
        kea_reservations = []
        
        reservations.each do |reservation|
          kea_reservation = {
            'hw-address' => reservation[:hw_address],
            'ip-address' => reservation[:ip_address]
          }
          
          kea_reservation['hostname'] = reservation[:hostname] if reservation[:hostname] && !reservation[:hostname].empty?
          
          kea_reservations << kea_reservation
        end
        
        kea_reservations
      rescue => e
        logger.error("Generate Kea reservations config failed: #{e.message}")
        []
      end
    end

    # Get activity logs
    def get_logs(limit = 100)
      begin
        db[:dhcp4_logs].order(Sequel.desc(:created_at)).limit(limit).all
      rescue => e
        logger.error("Get logs failed: #{e.message}")
        []
      end
    end

    private

    # Validate IP address format
    def valid_ip_address?(ip)
      return false unless ip.is_a?(String)
      
      parts = ip.split('.')
      return false unless parts.length == 4
      
      parts.all? do |part|
        begin
          num = Integer(part)
          num >= 0 && num <= 255
        rescue ArgumentError
          false
        end
      end
    end

    # Validate MAC address format
    def valid_mac_address?(mac)
      return false unless mac.is_a?(String)
      
      # Accept common MAC address formats
      mac_patterns = [
        /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/,  # XX:XX:XX:XX:XX:XX
        /^([0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}$/,  # XX-XX-XX-XX-XX-XX
        /^[0-9a-fA-F]{12}$/                        # XXXXXXXXXXXX
      ]
      
      mac_patterns.any? { |pattern| mac.match?(pattern) }
    end

    # Log database actions
    def log_action(action, details)
      begin
        db[:dhcp4_logs].insert(
          action: action,
          details: details.to_json,
          created_at: Time.now
        )
      rescue => e
        logger.error("Failed to log action: #{e.message}")
      end
    end
  end
end

# Initialize database on load
begin
  DatabaseManager.setup_database
rescue => e
  puts "Warning: Could not initialize database - #{e.message}"
end
