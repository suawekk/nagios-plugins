#!/usr/bin/env ruby
################################################################################
# Ruby x509 certificate  validity checker for nagios
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
    require 'openssl'
    require 'heredoc_unindent'
rescue => e
    puts "Exception occured when loading required gems: #{e}"
end

class X509CertChecker
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
        parse_opts
        check
    end

    def help
        puts <<-eod.unindent
        Ruby x509 certificate validity mass checker by Sławomir Kowalski <suawekk+github@gmail.com>
           
        Usage:
        #{$0} -g GLOB_PATTERN [ -w WARN_HOURS ] [ -c CRIT_HOURS ]  [ -h ]
        
        Exit codes:
        like any nagios check [ 0=OK,1=WARN,2=CRITICAL,3=UNKNOWN ]
        eod
    end

    def parse_opts
        OptionParser.new do |parser| 

            parser.on("-g","--glob GLOB_PATTERN",String,"Glob pattern used to search for certificates to check") do |arg|
                begin
                    @glob_pattern = arg
                rescue
                    @glob_pattern = nil
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

        unknown unless @unknowns.empty?
    end

    def get_cert_list(pattern)
        begin
            certs = Dir.glob(pattern)
        rescue => e
            @unknowns << "Failed to generate certificate list: #{e.message}"
            return false
        end

        return certs
    end

    def parse_cert(text)
        begin
            parsed = OpenSSL::X509::Certificate.new text
        rescue => e
            @errors << "Failed to parse certificate: #{e.message}"
            return false
        end
        parsed
    end

    def process(crt,name)
        diff = crt.not_after.to_i - DateTime.now.to_time.to_i
        diff_hours = (diff / 3660.0).to_i

        if diff_hours < 0
            return [EXIT_CRITICAL,"crt: #{name} expired at #{crt.not_after}!"]
        elsif diff_hours <= @crit_hours
            return [EXIT_CRITICAL,"crt #{name} will expire in #{diff_hours} hours at #{crt.not_after}"]
        elsif diff_hours <= @warn_hours
            return [EXIT_WARNING,"crt #{name} will expire in #{diff_hours} hours at #{crt.not_after}"]
        else
            return [EXIT_OK, "crt #{name} will expire in #{diff_hours} hours at #{crt.not_after}"]
        end
    end


    def process_all_certs(paths)
        results = {}

        paths.each do |path|
            results[path] = process_cert path
        end

        results
    end

    def process_cert(path)
        begin
            File.open(path) do |f|
                raw = f.read()
                instance = OpenSSL::X509::Certificate.new raw
                return process(instance,path)
            end
        rescue
            return false
        end
    end

    def process_results(results)
        criticals = []
        ok = []
        unknowns = []
        warnings = []

        results.each_pair do |file,result|
            case result[0]
            when EXIT_OK
                ok << result[1]
            when EXIT_WARNING
                warnings << result[1]
            when EXIT_CRITICAL
                criticals << result[1]
            when EXIT_UNKNOWN
                unknowns << result[1]
            end
        end

        if !criticals.empty?
            return [EXIT_CRITICAL,'check_certs OK',criticals]
        elsif !warnings.empty? 
            return [EXIT_WARNING,'check_certs WARNING',warnings]
        elsif !unknowns.empty?
            return [EXIT_UNKNOWN,'check_certs UNKNOWN',unknowns]
        else 
            return [EXIT_OK,'check_certs OK',["All #{ok.count} certificates are valid"]]
        end
    end

    def check
        certs = get_cert_list @glob_pattern

        unknown unless certs.instance_of?(Array)
        if certs.empty?
            @infos <<  "No certs found!"
        end

        results = process_all_certs certs

        aggregated_result = process_results results

        puts "%s: %s" % [aggregated_result[1],aggregated_result[2].join(',')]
        exit aggregated_result[0]

    end

end

X509CertChecker.new

