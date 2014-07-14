#!/usr/bin/env ruby
################################################################################
# Indexing checker nagios plugin
# This program gets list of urls to check and information whether they should
# be indexed. It checks whether each url is allowed or forbidden to be indexed
# by means of <meta name="robots"> tag and /robots.txt contents
#
# Author:: Sławomir Kowalski <suawekk@gmail.com>
# License:: Copyleft
################################################################################

VERSION=0.1
USER_AGENT="indexing-validator/#{VERSION}"

################################################################################
# We'll use Nagios-compatible exit codes
################################################################################
EXIT_OK         = 0
EXIT_WARNING    = 1
EXIT_CRITICAL   = 2
EXIT_UNKNOWN    = 3


################################################################################
# These are error messages for url processor
################################################################################
ERROR_MESSAGES = {
    url_parse: "Failed to parsed %s as uri",
    get_robots: "Failed to get robots for %s",
    unknown: "Unknown error occured when trying to process %s",
    meta_allows_indexing: "Meta tags allow indexing of %s",
    meta_disallows_indexing: "Meta tags forbid indexing of %s",
    robots_allow_indexing: "robots.txt allow indexing of %s",
    robots_disallow_indexing: "robots.txt forbid indexing of %s"
}

################################################################################
# This error code will be used for errors which don't have
# an entry in ERROR_MESSAGES
################################################################################
DEFAULT_ERROR = :unknown

################################################################################
# Try to load required gem(s)
################################################################################
begin
    require 'rubygems'
    require 'bundler/setup'
    require 'robots'
    require 'optparse'
    require 'ostruct'
    require 'net/http'
    require 'uri'
    require 'nokogiri'
    require 'json'
rescue => e
    puts "Failed to load required gem(s): #{e.message}"
    exit EXIT_UNKNOWN
end

################################################################################
# Default robots.txt path
################################################################################
ROBOTS_PATH='/robots.txt'

################################################################################
# XPATH selector for selecting <meta name="robots"> tag
# it uses XPath's translate function to find this tag
# regardless of its letter case
################################################################################
META_ROBOTS_TAG_SELECTOR='//meta[translate(@name,ABCDEFGHIJKLMNOPQRSTUVWXYZ,abcdefghijklmnopqrstuvwxyz)="robots"]'


class RobotsMatcherCheck
    def initialize

        @robots = {}
        @options = {
            file:       nil,
            mode:       nil,
            fail_on:    nil,
            debug:      FALSE,
            on_unknown: :unknown,
            max_error_messages: 3
        }

        parse_opts

        unless validate_opts
            error "Exiting because of invalid option(s)"
            exit EXIT_UNKNOWN
        end

        results = process_file @options[:file]
        process_results(results)
    end

    def process_results(results)

        # aggregate results by status code
        statuses = group_statuses(results)

        # some variables for code readability and DRY purposes
        criticals_no = statuses[:critical].count
        warnings_no = statuses[:warning].count
        unknowns_no = statuses[:unknown].count
        max = @options[:max_error_messages]

        if criticals_no > 0
            puts "CRITICAL: found %d criticals,%d unknowns in %d urls, listing %d critical(s):\n%s" % [
                criticals_no,
                unknowns_no,
                results.count,
                max > criticals_no ? criticals_no : @options[:max_error_messages],
                statuses[:critical].first(max).join("\n")
            ]
            exit EXIT_CRITICAL
        elsif warnings_no > 0
            puts "WARNING: found %d warnings,%d unknowns in %d urls, listing %d warning(s):\n%s" % [
                warnings_no,
                unknowns_no,
                results.count,
                max > warnings_no ? warnings_no : @options[:max_error_messages],
                statuses[:warning].first(max).join("\n")
            ]
            exit EXIT_WARNING
        elsif unknowns_no > 0
            puts "UNKNOWN: found %d unknowns in %d urls, listing %d unknown(s):\n%s" % [
                unknowns_no,
                results.count,
                max > unknowns_no ? unknowns_no : @options[:max_error_messages],
                statuses[:unknown].first(max).join("\n")
            ]
            exit EXIT_UNKNOWN
        end

        puts "OK: no errors found in %d urls" % results.count
        exit EXIT_OK
    end

    ################################################################################
    # Groups results by code
    # by processig data hash
    # in format :
    # {
    #   url1 => [:code1,["error1","error2"]],
    #   url2 => [:code1,["error3","error4"]],
    #   url3 => [:code3,["error5"]],
    # }
    # and returning aggregated results e.g :
    # {
    #   :code1 => ["error1","error2","error3","error4"]
    #   :code2 => ["error5"]
    # }
    #
    ################################################################################
    def group_statuses(data)
        results = {
            critical: [],
            unknown: [],
            warning: [],
        }

        data.each_pair { |k,v| results[v[0]] += v[1] unless v[1].nil? || !results.keys.include?(v[0])}

        return results
    end

    ################################################################################
    # Parses commandline options and sets up @options
    # hash containing either default or passed value
    # Note: this method doesn't do any validation of passed
    # options.
    ################################################################################
    def parse_opts
        OptionParser.new do |parser|
            parser.on("-d", "--debug") { @options[:debug] = TRUE }
            parser.on("-f", "--filename FILE") { |file| @options[:file]  = file}
            parser.on("-h", "--helpme","--wtf") { help ; exit EXIT_UNKNOWN}
            parser.on("-m", "--mode MODE",[:index,:noindex]) { |mode| @options[:mode] = mode }
            parser.on("-v", "--version") { version ;exit  EXIT_UNKNOWN }
            parser.on("-u", "--on-unknown ENUM",[:ok,:warning,:critical,:unknown]) do |action|
                @options[:on_unknown] = action
            end
        end.parse!
    end

    ################################################################################
    # Prints help message
    ################################################################################
    def help
        puts "Nagios HTTP Indexing check"
        puts "What does it do?"
        puts "This scripts takes file containing urls to check and mode (index|noindex)"
        puts "and checks each URL found in file according to index mode"
        puts
        puts "-What is checked?"
        puts "robots.txt content found on domain contained in URL"
        puts "meta 'robots' tag"
        puts ""
        puts "How do I use it?"
        puts "Usage: #{$0} -m index|noindex -f file.txt"
        puts
        puts "arguments:"
        puts "-m index|noindex       : sets whether URLS in file passed as argument to -f should be allowed to be indexed or not"
        puts "-f {file}              : sets source file path to {file}"
        puts "-u ok|warning|critical : override URL status when unknown error occurs when processing URL"
        puts "(e.g robots.txt couldn't be processed)"
        puts
        version
    end

    def version
        puts "Robots validator by suawek v.#{VERSION}"
    end

    ################################################################################
    # Checks whether passed option(s) are valid e.g whether passed valid filename
    # or indexing mode
    #
    ################################################################################
    def validate_opts
        if @options[:file].nil?
                puts "Pass me some filename (-f FILE)"
                return false
        elsif  !File.exists?(@options[:file])
                puts "File: #{@options[:file]} does not exist"
                return false
        elsif  !File.readable?(@options[:file])
                puts "File: #{@options[:file]} is not readable"
                return false
        elsif  File.directory?(@options[:file])
                puts "#{@options[:file]} is a directory!"
                return false
        elsif  File.zero?(@options[:file])
                puts "File: #{@options[:file]} is empty"
                return false
        end

        if @options[:mode].nil?
            puts "Pass me indexing mode (-m index|noindex )"
            return false
        end
        return true
    end


    ################################################################################
    # Retrieves and parses url
    # If parsing was successful and
    ################################################################################
    def get_meta(url)

        unless url.is_a? URI
            error "{url} (instance of #{url.class}) is not an URI instance!"
            return nil
        end

        begin
            body = Net::HTTP.get(url.host,url.request_uri)
            return nil unless body
        rescue => e
            error "Failed to request url: #{url} : #{e}"
            return nil
        end

        robots_arr = nil

        begin
            doc = Nokogiri::HTML(body)
            tags = doc.xpath(META_ROBOTS_TAG_SELECTOR)

            return nil if tags.nil? || tags.length == 0

            tag = tags.pop
            robots = tag["content"]

            return nil unless robots

            robots_arr = robots.gsub(/\s/,'').split(',')
        rescue => e
            error "Failed to get meta for #{url} : #{e}"
            return nil
        end

        # return lowercase values
        return robots_arr.map {|val| val.downcase}
    end

    ################################################################################
    # Tries to retrieve Robots instance for domain from cache (@robots hash)
    ################################################################################
    def get_robots(uri)

        unless uri.is_a? URI
            puts "argument #{uri} should be of type URI"
            return nil
        end

        obj = nil

        robots_id = robots_id(uri)

        unless @robots[robots_id].nil?
            return @robots[robots_id]
        end

        begin
            obj = Robots.new(USER_AGENT)
            @robots[robots_id] = obj
        rescue => e
            puts "Failed to initialize Robots class for #{uri}: #{e}"
            return nil
        end

    end

    ################################################################################
    # Processess file "filename" contents line-by line
    # by  stripping line trailers and calling proces_url on resulting string
    ################################################################################
    def process_file(filename)
        results = {}

        begin
            File.foreach(filename) do |line|
                if @options[:debug]
                    puts "processing: #{line}"
                end

                line.gsub!(/\W+$/,'');

                if url_ok(line)
                    results[line]  = process_url(line)

                    if @options[:debug]
                        puts JSON.pretty_generate(results)
                    end
                else
                    error "Not an absolute uri: #{line}"
                end
            end
        rescue => e
            error "Error when processing file: #{filename} : #{e.message}!"
            exit EXIT_UNKNOWN
        end

        return results
    end

    # Checks whether passed url is valid and absolute
    def url_ok(url)
        return url =~ URI::ABS_URI
    end


    def make_error_str(code,url)
        unless ERROR_MESSAGES.keys.include? code
            code = DEFAULT_ERROR
        end

        return ERROR_MESSAGES[code] % url
    end

    ################################################################################
    # Processes url - checks robots.txt and meta tags for information about
    # whether passed url is allowed or forbidden to be indexed
    ################################################################################
    def process_url(url)
        begin
            parsed = URI.parse(url)
        rescue => e
            return [FALSE,:url_parse,[e.to_s]]
        end

        robots = get_robots(parsed)
        meta = get_meta(parsed)

        if robots.nil?
            return [@options[:on_unknown],[make_error_str(:get_robots,url)]]
        end

        errors = []
        error = false
        result = []
        if @options[:mode] == :index
            if !meta.nil? && !meta_allows_indexing(meta,url)
                errors << make_error_str(:meta_disallows_indexing,url)
                error = true
            end

            unless robots_allow_indexing(robots,url)
                errors << make_error_str(:robots_disallow_indexing,url)
                error = true
            end
        elsif @options[:mode] == :noindex
            if !meta.nil? && meta_allows_indexing(meta,url)
                errors << make_error_str(:meta_allows_indexing,url)
                error = true
            end

            if robots_allow_indexing(robots,url)
                errors << make_error_str(:robots_allow_indexing,url)
                error = true
            end
        end

        result = error ? [:critical,errors] : [:ok]
        return result
    end

    def error(msg)
        STDERR.puts(msg)
    end

    def meta_allows_indexing(meta,url)
        return !meta.include?("noindex")
    end

    def robots_allow_indexing(robots,url)
        return robots.allowed?(url)
    end

    def robots_id(uri)
        return nil unless uri.is_a? URI
        return "#{uri.scheme}://#{uri.host}/"
    end

end

RobotsMatcherCheck.new
