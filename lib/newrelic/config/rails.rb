class NewRelic::Config::Rails < NewRelic::Config
  
  def app; :rails; end
  
  def env
    RAILS_ENV
  end
  def root
    RAILS_ROOT
  end
  
  def log_path
    path = ::RAILS_DEFAULT_LOGGER.instance_eval do
      File.dirname(@log.path) rescue File.dirname(@logdev.filename) 
    end rescue "#{root}/log"
    File.expand_path(path)
  end
  
  def start_plugin(rails_config=nil)
    if !tracers_enabled?
      require 'newrelic/shim_agent'
      return
    end
    start_agent
    install_developer_mode rails_config if developer_mode?
  end
  
  def install_developer_mode(rails_config)
    controller_path = File.join(newrelic_root, 'ui', 'controllers')
    helper_path = File.join(newrelic_root, 'ui', 'helpers')
    $LOAD_PATH << controller_path
    $LOAD_PATH << helper_path
    # Rails Edge
    if defined? ActiveSupport::Dependencies
      ActiveSupport::Dependencies.load_paths << controller_path
      ActiveSupport::Dependencies.load_paths << helper_path
    elsif defined? Dependencies.load_paths
      Dependencies.load_paths << controller_path
      Dependencies.load_paths << helper_path
    else
      to_stderr "ERROR: Rails version #{(RAILS_GEM_VERSION) ? RAILS_GEM_VERSION : ''} too old for developer mode to work."
      return
    end
    
    # This is a monkey patch to inject the developer tool route into the
    # parent app without requiring users to modify their routes. Of course this 
    # has the effect of adding a route indiscriminately which is frowned upon by 
    # some: http://www.ruby-forum.com/topic/126316#563328
    ActionController::Routing::RouteSet.class_eval do
      next if defined? draw_with_newrelic_map
      def draw_with_newrelic_map
        draw_without_newrelic_map do | map |
          puts "In NR mapper..."
          map.named_route 'newrelic_developer', '/newrelic/:action/:id', :controller => 'newrelic' unless NewRelic::Config.instance['skip_developer_route']
          yield map        
          puts "...out of NR mapper"
        end
      end
      alias_method_chain :draw, :newrelic_map
    end

    # If we have the config object then add the controller path to the list
    # Otherwise insert into the initializer to pick up the controller path
    # and add it to the default controller paths.  If the controller_paths
    # are overwritten then the dev mode controller will not be found
    if rails_config
      rails_config.controller_paths << controller_path
    else
      Rails::Initializer.class_eval do
        def default_controller_paths_with_newrelic
          paths = default_controller_paths_without_newrelic
          paths << controller_path
          paths
        end
        alias_method_chain :default_controller_paths, :newrelic
      end
    end

    #ActionController::Routing::Routes.reload! unless NewRelic::Config.instance['skip_developer_route']
    
    # inform user that the dev edition is available if we are running inside
    # a webserver process
    if local_env.identifier
      port = local_env.identifier.to_s =~ /^\d+/ ? ":#{port}" : ":port" 
      to_stderr "NewRelic Agent (Developer Mode) enabled."
      to_stderr "To view performance information, go to http://localhost#{port}/newrelic"
    end
  end
  
  # Collect the Rails::Info into an associative array as well as the list of plugins
  def gather_info
    i = [[:app, app]]
    begin 
      begin
        require 'rails/info'
      rescue LoadError
        require 'builtin/rails_info/rails/info'
      end
      i += ::Rails::Info.properties
    rescue SecurityError, ScriptError, StandardError => e
      log.debug "Unable to get the Rails info: #{e.inspect}"
    end
    
    # Would like to get this from config, but how?
    plugins = Dir[File.join(File.expand_path(__FILE__+"/../../../../.."),"/*")].collect { |p| File.basename p }
    i << ['Plugin List', plugins]
    
    # Look for a capistrano file indicating the current revision:
    rev_file = File.expand_path(File.join(RAILS_ROOT, "REVISION"))
    if File.readable?(rev_file) && File.size(rev_file) < 64
      File.open(rev_file) { | file | i << ['Revision', file.read] } rescue nil
    end
    i
  end
end