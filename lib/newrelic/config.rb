require 'yaml'
require 'newrelic/version'
require 'newrelic/local_environment'
require 'singleton'

# Configuration supports the behavior of the agent which is dependent
# on what environment is being monitored: rails, merb, ruby, etc
# It is an abstract factory with concrete implementations under
# the config folder.
module NewRelic
  class Config
    
    def self.instance
      @instance ||= new_instance
    end

    @settings = nil
    
    # Initialize the agent: install instrumentation and start the agent if
    # appropriate.  Subclasses may have different arguments for this when
    # they are being called from different locations.
    def start_plugin(*args)
      if tracers_enabled?
        start_agent
      else
        require 'newrelic/shim_agent'
      end
    end
    
    # Collect miscellaneous interesting info about the environment
    def gather_info
      [[:app, app]]
    end
    
    def [](key)
      fetch(key)
    end
    
    def fetch(key, default=nil)
      @settings[key].nil? ? default : @settings[key]
    end
    
    ###################################
    # Agent config conveniences
    
    def newrelic_root
      File.expand_path(File.join(__FILE__, "..","..",".."))
    end
    def connect_to_server?
      fetch('enabled', nil)
    end
    def developer_mode?
      fetch('developer', nil)
    end
    def tracers_enabled?
      !(ENV['NEWRELIC_ENABLE'].to_s =~ /false|off|no/i) &&
       (developer_mode? || connect_to_server?)
    end
    
    def to_s
      puts self.inspect
      "Config[#{self.app}]"
    end
    def log
      @log
    end
    
    def setup_log(identifier)
      log_file = "#{log_path}/#{log_file_name(identifier)}"
      @log = Logger.new log_file
      
      # change the format just for our logger
      
      def @log.format_message(severity, timestamp, progname, msg)
        "[#{timestamp.strftime("%m/%d/%y %H:%M:%S")} (#{$$})] #{severity} : #{msg}\n" 
      end
      
      # set the log level as specified in the config file
      case fetch("log_level","info").downcase
        when "debug": @log.level = Logger::DEBUG
        when "info": @log.level = Logger::INFO
        when "warn": @log.level = Logger::WARN
        when "error": @log.level = Logger::ERROR
        when "fatal": @log.level = Logger::FATAL
      else @log.level = Logger::INFO
      end
      log! "New Relic RPM Agent #{NewRelic::VERSION::STRING} Initialized: pid = #{$$}"
      log! "Agent Log is found in #{log_file}"
      @log
    end
    
    def local_env
      @env ||= NewRelic::LocalEnvironment.new
    end

    # send the given message to STDERR so that it shows
    # up in the console.  This should be used for important informational messages at boot.
    # The to_stderr may be implemented differently by different config subclasses.
    def log!(msg, level=:info)
      to_stderr msg
      log.send level, msg if log
    end
    
    protected
    def to_stderr(msg)
      STDERR.puts "** [NewRelic] " + msg 
    end
    
    def start_agent
      require 'newrelic/agent'
      NewRelic::Agent::Agent.instance.start(local_env.environment, local_env.identifier)
    end
    
    def config_file
      File.expand_path(File.join(root,"config","newrelic.yml"))
    end
    
    def log_path
      path = File.join(root,'log')
      unless File.directory? path
        path = '.'
      end
      File.expand_path(path)
    end
    def log_file_name(identifier)
      identifier_part = identifier && identifier[/[\.\w]*$/] 
      "newrelic_agent.#{identifier_part ? identifier_part + "." : "" }log"
    end

    # Create the concrete class for environment specific behavior:
    def self.new_instance
      case
      when defined? NewRelic::TEST
        require 'config/test_config'
        NewRelic::Config::Test.new
      when defined? Merb::Plugins then
        require 'newrelic/config/merb'
        NewRelic::Config::Merb.new
      when defined? Rails then
        require 'newrelic/config/rails'
        NewRelic::Config::Rails.new
      else
        require 'newrelic/config/ruby'
        NewRelic::Config::Ruby.new
      end
    end
    
    # Return a hash of settings you want to override in the newrelic.yml
    # file.  Maybe just for testing.
    
    def initialize
      newrelic_file = config_file
      if !File.exists?(config_file)
        log! "Cannot find newrelic.yml file at #{newrelic_file}."
        newrelic_file = File.expand_path(File.join(__FILE__,"..","..","..","newrelic.yml"))
        log! "Using #{newrelic_file} file."
        log! "Signup at rpm.newrelic.com to get a newrelic.yml file configured for a free Lite account."
      end
      begin
        cfile = File.read(newrelic_file)
        @settings = YAML.load(cfile)[env] || {}
      rescue ScriptError, StandardError => e
        raise "Error reading #{newrelic_file}: #{e}"
      end
    end
    
  end  
end