#!/usr/bin/env ruby
################################################################################
# Ruby CRL validity checker for nagios
#
# Author: Sławomir Kowalski <suawekk+github@gmail.com>
#
# License: I don't care - just don't tell this script  is your own work 
# and I'll be fine with that. Not removing this comment would also be nice
# but if you really hate it don't hesitiate to remove it.
################################################################################

begin
    require 'rubygems'
    require 'optparse'
    require 'optparse/time'
    require 'ostruct'
    require 'yaml'
    require 'net/http'
    require 'openssl'
    require 'uri'
    require 'colorize'
    require 'heredoc_unindent'
rescue => e
    puts "Exception occured when loading required gems: #{e}"
end

class X509CrlChecker
    EXIT_OK         = 0
    EXIT_WARNING    = 1
    EXIT_CRITICAL   = 2
    EXIT_UNKNOWN    = 3

    def initialize
        @warn_hours = 24 * 7
        @crit_hours = 24
        @pad_length = 5
        @infos = []
        @unknowns = []
        @warnings = []
        @errors = []
        @timeout = 120
        parse_opts
        check
    end

    def help
        puts <<-eod.unindent
        Ruby x509 CRL checker by Sławomir Kowalski <suawekk+github@gmail.com>
           
        Usage:
        #{$0} -u URL [ -t TIMEOUT_SECS ] [ -w WARN_HOURS ] [ -c CRIT_HOURS ]  [ -h ]
        
        Exit codes:
        like any nagios check [ 0=OK,1=WARN,2=CRITICAL,3=UNKNOWN ]
        eod
    end

    def parse_opts
        OptionParser.new do |parser| 

            parser.on("-u","--url URL",String,"URL pointing to crl to be checked") do |arg|
                begin
                    @uri = URI.parse(arg)
                rescue
                    @uri = nil
                end
            end

            parser.on("-w","--warn WARN_HOURS",Integer,"warning threshold in hours") do |arg|
                @warn_hours = arg.to_i
            end
            parser.on("-c","--crit CRIT_HOURS",Integer,"critical threshold in hours") do |arg|
                @crit_hours = arg.to_i
            end

            parser.on("-h","--help","show help") do
                  help
                  exit EXIT_UNKNOWN
            end

        end.parse!

        unless @uri.to_s =~ URI::regexp
            @unknowns << "Invalid URI passed!"
        end
        
        if @crit_hours < 0
            @unknowns << "No negative critical threshold allowed!"
        end

        if @warn_hours < 0
            @unknowns << "No negative warning threshold allowed!"
        end

        if @crit_hours >= @warn_hours
            @unknowns << "Warning threshold should be higher than critical threshold"
        end

        unknown unless @unknowns.empty?
    end

    def retrieve_crl(uri)
        begin
            http = Net::HTTP.new(uri.host,uri.port)
            http.read_timeout = @timeout

            response = http.get(uri.path)

            case response 
            when Net::HTTPSuccess
                return response.body
            else
                @unknowns << "HTTP request failed, response code is #{response.code}"
                return false
            end

        rescue Timeout::Error => e
            @unknowns << "Read timeout from #{uri.to_s}"
            return false
        rescue => e
            @unknowns << "Failed to retrieve uri: #{e.message}"
            return false
        end

        return  response
    end

    def parse_crl(text)
        begin
            parsed = OpenSSL::X509::CRL.new(text)
        rescue => e
            @errors << "Failed to parse crl: #{e.message}"
            return false
        end
        parsed
    end

    def process(crl)
        unless crl.instance_of?(OpenSSL::X509::CRL)
            @unknowns << "Internal Error"
            unknown
        end

        diff = crl.next_update.to_i - DateTime.now.to_time.to_i
        diff_hours = (diff / 3660.0).to_i

        if diff_hours < 0
            @errors << "CRL: #{@uri} expired at #{crl.next_update}!"
            error
        elsif diff_hours <= @crit_hours
            @errors << "CRL #{@uri} will expire in #{diff_hours} hours at #{crl.next_update}"
            error
        elsif diff_hours <= @warn_hours
            @warnings << "CRL #{@uri} will expire in #{diff_hours} hours at #{crl.next_update}"
            warning
        else
            @infos << "CRL #{@uri} will expire in #{diff_hours} hours at #{crl.next_update}"
            ok
        end
    end

    def status(desc,code=EXIT_OK)
            additional = ''

            if code == EXIT_OK
                additional = @infos.join(',')
            elsif code == EXIT_WARNING
                additional = @warnings.join(',')
            elsif code == EXIT_CRITICAL
                additional = @errors.join(',')
            else
                additional = @unknowns.join(',')
            end

            puts "CHECK_CRL #{desc.upcase}: #{additional}"
            exit code
    end

    def unknown
        status 'unknown',3
    end

    def error
        status 'critical',2
    end

    def warning
        status 'warning',1
    end

    def ok
        status 'ok',0
    end

    def check
        raw = retrieve_crl @uri

        unknown unless raw

        parsed = parse_crl raw

        process parsed
    end

end

X509CrlChecker.new
