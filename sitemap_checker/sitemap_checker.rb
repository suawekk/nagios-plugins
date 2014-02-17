#!/usr/bin/env ruby

VERSION=0.1
AUTHOR="suawek"
CHECK_NAME="CHECK_SITEMAP"
USER_AGENT = "sitemap_checker v.#{VERSION}, Ruby #{RUBY_VERSION}/#{RUBY_PLATFORM}"
LOCATION_CSS_SELECTOR='urlset > url > loc'

EXIT_OK=0
EXIT_WARN=1
EXIT_CRIT=2
EXIT_UNK=3

begin
    require 'rubygems'
    require 'bundler/setup'
    require 'nokogiri'
    require 'net/http'
    require 'optparse'
    require 'heredoc_unindent'
    require 'curb'
rescue LoadError => e
    STDERR.puts "Failed to load required gems - #{e.message}!"
rescue => e
    STDERR.puts "Unknown error occured during gem loading - #{e.message}"
    exit EXIT_UNK
end

class SitemapChecker

    def initialize
        @options = {
            :verbose => FALSE,
            :validate => TRUE,
            :retries => 3,
            :timeout => 30,
            :useragent => $USER_AGENT,
            :url => nil,
            :minlocations => 0
        }
    end

    def parse_opts(results)

        unless results.kind_of?(Hash)
            results = Hash.new
        end

        errors = Array.new

        OptionParser.new do |opts|
            opts.on('-h', '--help') do
                help
            end
            opts.on('-u', '--url URL') do |url|

                begin
                    parsed_url = URI.parse(url)
                rescue => e
                    errors << "Unable to parse %s as URI!, error is: %s" % [url,e.message]
                end

                @options[:url] = parsed_url
            end
            opts.on('-m', '--minlocations MINLOCATIONS',Integer) do |minlocations|
                @options[:minlocations] = minlocations
            end
            opts.on('-t', '--timeout TIMEOUT',Integer) do |timeout|
                @options[:timeout] = timeout
            end

        end.parse!

        if errors.empty?
            return true
        else
            STDERR.puts "Found %d error(s) during argument check:" % [errors.count]

            for x in errors
                STDERR.puts "#{x}"
            end

            return false
        end
    end

    def validate(str,validation_errors)

        doc = Nokogiri::XML str do |config|
            config.strict
        end


        for error in doc.errors
            validation_errors << error
        end


        locs_num = nil

        if @options[:minlocations] > 0 
            locs_num = count_url_locs(doc)

            if locs_num < @options[:minlocations]
                validation_errors << "sitemap has not enough locations (%d < %d)" % [locs_num,@options[:minlocations]]
            end
        end

        return validation_errors.empty?
    end

    def run!
        parse_results = Hash.new
        unless parse_opts(parse_results)

        end

        body = ""
        fetch_out = fetch(@options[:url])
        code = fetch_out[0]
        body = fetch_out[1]

        if (code != 200)
            puts "#{CHECK_NAME} CRITICAL: server returned : #{code}"
            exit EXIT_CRIT
        end

        validation_errors = []
        valid = validate(body,validation_errors)

        if @options[:validate] == FALSE
            puts "#{CHECK_NAME} OK : server returned #{code}, validation skipped"
            exit EXIT_OK
        elsif valid
            puts "#{CHECK_NAME} OK : server returned #{code}, validation sucessful"
            exit EXIT_OK
        else
            puts "#{CHECK_NAME} CRITICAL : server returned #{code}, validation failed: #{validation_errors.join(",")}"
            exit EXIT_CRIT
        end
    end

    def help
        puts <<-EOD.unindent
            Sitemap checker v.#{VERSION} by #{AUTHOR}
            Usage: #{$0}
                -u SITEMAP_URL | --url SITEMAP_URL
                [ -h | --help ]
                [ -t TIMEOUT_SECS | --timeout TIMEOUTS_SECS ]
                [ -n | --no-validate]
                [ -r RETRIES | --retries RETRIES ]
                [ -m  MINLOCATIONS | --minlocations MINLOCATIONS ]
        EOD
    end

    def fetch(url)
        return false if url.nil?

        begin
        c = Curl::Easy.perform(url.to_s) do |curl|
            curl.headers["User-Agent"] = @options[:useragent]
            curl.follow_location = TRUE
            curl.timeout = @options[:timeout]
        end
        rescue Curl::Err::TimeoutError => e
            puts "#{CHECK_NAME} CRITICAL: server timed out after #{@options[:timeout]} secs"
            exit EXIT_CRIT
        rescue => e
            puts "#{CHECK_NAME} CRITICAL: HTTP Request Error: #{e.message}"
            exit EXIT_CRIT
        end

        return [c.response_code,c.body_str]
    end

    def count_url_locs(doc)
        return nil unless doc.instance_of? Nokogiri::XML::Document
        return doc.css(LOCATION_CSS_SELECTOR).count
    end

end

SitemapChecker.new.run!
