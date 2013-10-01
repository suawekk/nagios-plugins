#!/usr/bin/env ruby
################################################################################
# Redis master/slave switcher script by suawekk <suawekk+github@gmail.com>
# What does it do?
# It checks or sets master/slave role for selected Redis server
# It's quicker than scripted netcat because it doesn't need dummy delays
#
# License: I don't care - just don't tell this script  is your own work 
# and I'll be fine with that. Not removing this comment would also be nice
# but if you really hate it don't hesitiate to remove it.
################################################################################

begin
    require 'rubygems'
    require 'optparse'
    require 'optparse/time'
    require 'redis'
    require 'ostruct'
rescue => e
    puts "Exception occured when loading required gems: #{e}"
end

class RedisChecker  
    EXIT_OK         = 0
    EXIT_WARNING    = 1
    EXIT_CRITICAL   = 2
    EXIT_UNKNOWN    = 3

    ROLES =  [:master,:slave]
    COMMANDS = [:check,:set]
    LINK_STATUS= [:up,:down]


    def initialize

        #set some same defaults for instance variables ...
        @host = 'localhost'
        @port = 6379
        @role = nil
        @command = nil
        @client = nil
        @timeout = 5.0

        parse_opts
        init_client
        run!
    end

    def parse_opts
        OptionParser.new do |parser| 
            parser.on("-h","--host HOST","Execute commands on HOST") do |arg|
                @host = arg
            end

            parser.on("-p","--port PORT",Integer,"PORT on which is HOST listening") do |arg|
                @port = arg
            end
            
            parser.on("-r","--role [ROLE]",ROLES,"target ROLE (#{ROLES.join(',')})") do |arg|
                @role = arg
            end

            parser.on("-c","--command [COMMAND]",COMMANDS,"command to execute (#{COMMANDS.join(',')})") do |arg|
                @command = arg
            end

            parser.on("-t","--timeout TIMEOUT",Float,"command timeout (seconds)") do |arg|
                @timeout = arg
            end

            parser.on("-m","--master MASTER",String,"replication master host (Host:Port)") do |arg|
                @master_host,@master_port = arg.split(':')
            end

        end.parse!


        unless COMMANDS.include?(@command)
            puts "Unrecognized command!"
            exit EXIT_UNKNOWN
        end

        unless ROLES.include?(@role)
            puts "Unrecognized role!"
            exit EXIT_UNKNOWN
        end

        if @role == :slave
            if @master_host.nil? 
                puts "No master host!"
                exit EXIT_UNKNOWN
            end

            @master_port = @master_port.to_i

            if @master_port.nil?
                puts "No master port!"
                exit EXIT_UNKNOWN
            elsif !(1..65535).include?(@master_port)
                puts "Port has to be integer between 0-65535!"
                exit EXIT_UNKNOWN
            end
        end

    end

    def init_client
        begin
            @client = Redis.new({
                :host       => @host,
                :port       => @port,
                :timeout    => @timeout
            })
            return !@client.nil?

        rescue => e
            puts "Exception occured when initializing Redis client instance : #{e}"
            exit EXIT_CRITICAL
            return false
        end


    end

    def info
       @client.info
    end

    def check
        if @role == :master
            check = @client.info
            result = check_master
        elsif @role == :slave
            result = check_slave_replication(@master_host,@master_port)
        end
        
        if result['status']
            puts "OK"
        else
            puts "FAIL: #{result['errors'].join(',')}"
        end

        exit result['status'] == true ? EXIT_CRITICAL : EXIT_OK

    end

    def check_master
        info = @client.info
        
        result = {
            'status'    => true,
            'errors'    => [],
        }

        if info['role'] != :master.to_s
            result['status'] = false
            result['errors'] << "Not a master"
        end

        return result
    end

    def check_slave_replication(master_host,master_port,max_delay = 0)
        info = @client.info
        
        result = {
            'status'    => true,
            'errors'    => [],
        }

        if info['role'] != :slave.to_s
            result['status'] = false
            result['errors'] << "Not a slave"
            return result
        end

        if info['master_host'] != master_host
            result['errors'] << "wrong master host (returned: #{info['master_host']},expected: #{master_host})"
        end

        if info['master_port'].to_i != master_port
            result['errors'] << "wrong master port (returned: #{info['master_port'].to_i},expected: #{master_port})"
        end

#        if info['master_link_status'] != 'up'
#            result['errors'] << "master link is down since #{Time.strptime(info['master_link_down_since_seconds'],'%s').iso8601}"
#        end

        result['status'] = result['errors'].empty?
        result
    end

    def set
        if @role == :master
            @client.slaveof('no','one')
        elsif @role == :slave
            @client.slaveof(@master_host,@master_port)
        end

        result = check
        
        if result['status']
            puts "OK"
        else
            puts "FAIL: #{result['errors'].join(',')}"
        end

        exit result['status'] == true ? 1 : 0
    end

    def run!
        if  @command == :check
            check
        elsif @command == :set
            set
        end
    end
end

RedisChecker.new
