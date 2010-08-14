
require 'net/http'
require 'fileutils'

if Redcar.platform == :windows
  require "rubygems"
  require "zip/zipfilesystem"
end

module Redcar
  class Installer
    def initialize
      if ENV['http_proxy']
        proxy = URI.parse(ENV['http_proxy'])
        @connection = Net::HTTP::Proxy(proxy.host, proxy.port, proxy.user, proxy.password)
      else
        @connection = Net::HTTP
      end
      puts "found latest XULRunner release version: #{xulrunner_version}" if Redcar.platform == :windows
    end
  	
  	def install
  	  unless File.writable?(JRUBY_JAR_DIR)
  	    puts "Don't have permission to write to #{JRUBY_JAR_DIR}. Please rerun with sudo."
  	    exit 1
  	  end
      Redcar.environment = :user
  	  puts "Downloading >10MB of jar files. This may take a while."
  	  grab_jruby
  	  grab_common_jars
  	  grab_platform_dependencies
  	  grab_redcar_jars
      puts "Building textmate bundle cache"
      s = Time.now
      load_textmate_bundles
      puts "... took #{Time.now - s}s"
      fix_user_dir_permissions
  	  puts
  	  puts "Done! You're ready to run Redcar."
  	end
  
    def associate_with_any_right_click
      raise 'this is currently only for windows' unless Redcar.platform == :windows      
      require 'rbconfig'
      require 'win32/registry'
      # associate it with the current rubyw.exe
      rubyw_bin = File.join([Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name']]) << 'w' << Config::CONFIG['EXEEXT']
      if rubyw_bin.include? 'file'
        raise 'this must be run from a ruby exe, not a java -cpjruby.jar command'
      end
      rubyw_bin.gsub!('/', '\\') # executable names wants back slashes
      for type, english_text  in {'*' => 'Open with Redcar', 'Directory' => 'Open with Redcar (dir)'}
        name = Win32::Registry::HKEY_LOCAL_MACHINE.create "Software\\classes\\#{type}\\shell\\open_with_redcar"
        name.write_s nil, english_text
        dir = Win32::Registry::HKEY_LOCAL_MACHINE.create "Software\\classes\\#{type}\\shell\\open_with_redcar\\command"
        command = %!"#{rubyw_bin}" "#{File.expand_path($0)}" "%1"!
        dir.write_s nil, command
      end
      puts 'Associated.'
    end

    def plugins_dir
      File.expand_path(File.join(File.dirname(__FILE__), %w(.. .. plugins)))
    end
    
    ASSET_HOST = "http://redcar.s3.amazonaws.com"
    
    JFACE = %w(
      /jface/org.eclipse.core.commands.jar
      /jface/org.eclipse.core.runtime_3.5.0.v20090525.jar
      /jface/org.eclipse.equinox.common.jar
      /jface/org.eclipse.jface.databinding_1.3.0.I20090525-2000.jar
      /jface/org.eclipse.jface.jar
      /jface/org.eclipse.jface.text_3.5.0.jar
      /jface/org.eclipse.osgi.jar
      /jface/org.eclipse.text_3.5.0.v20090513-2000.jar
      /jface/org.eclipse.core.resources.jar
      /jface/org.eclipse.core.jobs.jar
    )
    
    def redcar_jars_dir
      File.expand_path(File.join(Redcar.user_dir, "jars"))
    end
    
    JRUBY_JAR_DIR = File.expand_path(File.join(File.dirname(__FILE__), ".."))
    
    JRUBY = [
      "/jruby/jcodings.jar",
      "/jruby/jdom.jar",
      "/jruby/joni.jar"
    ]

    JRUBY << "http://jruby.org.s3.amazonaws.com/downloads/1.5.1/jruby-complete-1.5.1.jar"
    
    JOPENSSL_DIR = File.expand_path(File.join(File.dirname(__FILE__), "..", "openssl/lib/")) 
    JOPENSSL = {
      "/jruby/bcmail-jdk14-139-redcar1.jar" => "bcmail-jdk14-139.jar",
      "/jruby/bcprov-jdk14-139-redcar1.jar" => "bcprov-jdk14-139.jar",
      "/jruby/jopenssl-redcar1.jar"         => "jopenssl.jar",
    }

    REDCAR_JARS = {
      "/java-mateview-#{Redcar::VERSION}.jar" => "plugins/edit_view_swt/vendor/java-mateview.jar",
      "/application_swt-#{Redcar::VERSION}.jar" => "plugins/application_swt/lib/dist/application_swt.jar",
      "/clojure-1.2beta1.jar" => "plugins/repl/vendor/clojure.jar",
      "/clojure-contrib-1.2beta1.jar" => "plugins/repl/vendor/clojure-contrib.jar",
      "/org-enclojure-repl-server.jar" => "plugins/repl/vendor/org-enclojure-repl-server.jar"
      
    }
    
    def xulrunner_uri
      "http://releases.mozilla.org/pub/mozilla.org/xulrunner/releases/#{xulrunner_version}/runtimes/xulrunner-#{xulrunner_version}.en-US.win32.zip"
    end

    SWT_JARS = {
      :osx     => {
        "/swt/osx.jar"     => "osx/swt.jar",
        "/swt/osx64.jar"   => "osx64/swt.jar"
      },
      :linux   => {
        "/swt/linux.jar"   => "linux/swt.jar",
        "/swt/linux64.jar" => "linux64/swt.jar"
      },
      :windows => {
        "/swt/win32.jar"   => "win32/swt.jar",
      }
    }
    
    def grab_jruby
      puts "* Checking JRuby dependencies"
      
      setup "jruby",    :resources => JRUBY,    :path => JRUBY_JAR_DIR
      setup "jopenssl", :resources => JOPENSSL, :path => JOPENSSL_DIR
    end
    
    def grab_common_jars
      puts "* Checking common jars"
      
      setup "jface", :resources => JFACE, :path => File.join(plugins_dir, %w(application_swt vendor jface))
    end
    
    def grab_platform_dependencies
      puts "* Checking platform-specific SWT jars"
      case Config::CONFIG["host_os"]
      when /darwin/i
        setup "swt", :resources => SWT_JARS[:osx],     :path => File.join(plugins_dir, %w(application_swt vendor swt))

      when /linux/i
        setup "swt", :resources => SWT_JARS[:linux],   :path => File.join(plugins_dir, %w(application_swt vendor swt))

      when /windows|mswin|mingw/i
        setup "swt", :resources => SWT_JARS[:windows], :path => File.join(plugins_dir, %w(application_swt vendor swt))
        setup "swt", :resources => [xulrunner_uri],    :path => File.expand_path(File.join(File.dirname(__FILE__), %w(.. .. vendor)))
        link( File.join(redcar_jars_dir, "xulrunner"),
              File.expand_path(File.join(File.dirname(__FILE__), %w(.. .. vendor xulrunner))))
      end
    end
    
    def grab_redcar_jars
      puts "* Checking Redcar jars"
      setup "redcar", :resources => REDCAR_JARS, :path => File.join(File.dirname(__FILE__), "..", "..")
    end
    
    def download(uri, path)
      if uri =~ /^\//
        uri = ASSET_HOST + uri
      end
      print "  downloading #{uri}... "; $stdout.flush
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "wb") do |write_out|
        write_out.print @connection.get(URI.parse(uri))
      end
      
      if File.open(path).read(200) =~ /Access Denied/
        puts "\n\n*** Error downloading #{uri}, got Access Denied from S3."
        FileUtils.rm_rf(path)
        exit
      end
      
      if path =~ /.*\.zip$/
      	print "done!\n  unzipping  #{path}..."; $stdout.flush
      	Installer.unzip_file(path)
      end
      puts "done!"
    end
    
    def setup(name, options)
      resources   = options.delete(:resources)
      target_dir  = options.delete(:path)
      
      if resources.is_a?(Array)
        resources.each do |resource|
          setup_resource(name, target_dir, resource, File.basename(resource))
        end
      else
        resources.each do |url_path, target_path|
          setup_resource(name, target_dir, url_path, target_path)
        end
      end
    end
    
    def setup_resource(name, target_dir, url_path, target_path)
      target_file = File.join(target_dir, target_path)
      return if File.exist?(target_file)
      
      cached = File.join(redcar_jars_dir, File.basename(url_path))
      unless File.exists?(cached)
        download(url_path, cached)
      end

      FileUtils.mkdir_p File.dirname(target_file)
      link(cached, target_file)
    end

    def link(cached, target)
      # Windoze doesn't support FileUtils.ln_sf, so we copy the files
      if Config::CONFIG["host_os"] =~ /windows|mswin|mingw/i
        print "  copying #{File.basename(cached)}... "
        $stdout.flush
        FileUtils.cp_r cached, target
        puts "done"
      else
        print "  linking #{File.basename(cached)}... "
        $stdout.flush
        FileUtils.ln_sf cached, target
        puts "done"
      end
    end
    
    # unzip a .zip file into the directory it is located
    def self.unzip_file(source)
      source = File.expand_path(source)
      Dir.chdir(File.dirname(source)) do
        Zip::ZipFile.open(source) do |zipfile|
          zipfile.entries.each do |entry|
            FileUtils.mkdir_p(File.dirname(entry.name))
            begin
              entry.extract
            rescue Zip::ZipDestinationFileExistsError
            end
          end
        end
      end
    end
    
    def load_textmate_bundles
      $:.unshift("#{File.dirname(__FILE__)}/../../plugins/core/lib")
      $:.unshift("#{File.dirname(__FILE__)}/../../plugins/textmate/lib")
      require 'core'
      Redcar.environment = :user
      Core.loaded
      require 'textmate'
      Redcar::Textmate.all_bundles
    end
    
    def fix_user_dir_permissions
      desired_uid = File.stat(Redcar.home_dir).uid
      desired_gid = File.stat(Redcar.home_dir).gid
      FileUtils.chown_R(desired_uid, desired_gid.to_s, Redcar.user_dir)
    end
    
    def xulrunner_version
      @xulrunner_version ||= begin
        html = @connection.get(URI.parse("http://releases.mozilla.org/pub/mozilla.org/xulrunner/releases/"))
        html.scan(/\d\.\d\.\d\.\d+/).sort.reverse.first
      end
    end
  end
end


