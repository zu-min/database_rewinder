require_relative 'database_rewinder/cleaner'

module DatabaseRewinder
  VERSION = Gem.loaded_specs['database_rewinder'].version.to_s

  class << self
    # Set your DB configuration here if you'd like to use something else than the AR configuration
    attr_writer :database_configuration

    def init
      @cleaners, @table_names_cache, @clean_all, @only, @except, @database_configuration = [], {}, false
    end

    def database_configuration
      @database_configuration || ActiveRecord::Base.configurations
    end

    def create_cleaner(connection_name)
      config =  database_configuration[connection_name.to_sym] ||
                  database_configuration[Padrino.env][connection_name.to_s] ||
                  database_configuration[Padrino.env][connection_name.to_s.split('.')[0]][connection_name.to_s.split('.')[1]]

      raise %Q[Database configuration named "#{connection_name}" is not configured.] unless config

      Cleaner.new(config: config, connection_name: connection_name, only: @only, except: @except).tap {|c| @cleaners << c}
    end

    def [](_orm, connection: nil, **)
      @cleaners.detect {|c| c.connection_name == connection} || create_cleaner(connection)
    end

    def all=(v)
      @clean_all = v
    end

    def cleaners
      create_cleaner 'test' if @cleaners.empty?
      @cleaners
    end

    def record_inserted_table(connection, sql)
      config = connection.instance_variable_get(:'@config')
      database = config[:database]
      #NOTE What's the best way to get the app dir besides Rails.root? I know Dir.pwd here might not be the right solution, but it should work in most cases...
      root_dir = defined?(Rails) ? Rails.root : Dir.pwd
      cleaner = cleaners.detect do |c|
        if (config[:adapter] == 'sqlite3') && (config[:database] != ':memory:')
          File.expand_path(c.db, root_dir) == File.expand_path(database, root_dir)
        else
          c.db == database
        end
      end or return

      match = sql.match(/\AINSERT INTO [`"]?([^\s`"]+)[`"]?/i)
      table = match[1] if match
      if table
        cleaner.inserted_tables << table unless cleaner.inserted_tables.include? table
        cleaner.pool ||= connection.pool
      end
    end

    def clean
      if @clean_all
        clean_all
      else
        cleaners.each {|c| c.clean}
      end
    end

    def clean_all
      cleaners.each {|c| c.clean_all}
    end

    # cache AR connection.tables
    def all_table_names(connection)
      db = connection.pool.spec.config[:database]
      @table_names_cache[db] ||= connection.tables.reject{|t| t == ActiveRecord::SchemaMigration.table_name }
    end
  end
end

begin
  require 'rails'
  require_relative 'database_rewinder/railtie'
rescue LoadError
  DatabaseRewinder.init
  require_relative 'database_rewinder/active_record_monkey'
end
