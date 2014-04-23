#!/usr/bin/env ruby
################################################################################
# Nagios checker v.0.1 by suawek <suawekk+github@gmail.com>
# License: Honestly I don't care about licensing - just don't tell everyone
# that you wrote this check, and I'll probably be fine.
#
# Requirements: required gems are listed in Gemfile distributed with this script
# Use "bundle install" or something like that to install dependencies.
#
# Disclaimer:
# I don't provide any warranties that this program will work for you, however
# if somethings seems weird you can probably just ask me about that.
#
################################################################################
begin
    require 'optparse'
    require 'rubygems'
    require 'bundler/setup'
    require 'whois'
    require 'nagiosplugin'
    require 'unindent'
rescue => e
    STDERR.puts "Failed to load required gem(s):  #{e.message}"
    exit 1
end

class Whois_Check < NagiosPlugin::Plugin

    #
    # Constructor calls whois_lookup only when passed
    # options are valid to reduce WHOIS servers load
    #
    def initialize
        parse_opts
        validate_opts && whois_lookup(@options[:domain])
    end

    #
    # Parses commandline options using OptionParser
    #
    def parse_opts
        @options = {
            :crit_days => 30,
            :warn_days => 60,
            :verbose => false,
            :domain => nil
        }

        OptionParser.new do |opts|
            opts.banner =<<-EOD.unindent!
            Usage: #{$0} -d DOMAIN -w WARNING -c CRITICAL
            EOD

            opts.on "-c","--crit CRIT_DAYS",Integer do |c|
                @options[:crit_days]  = c.to_i
            end

            opts.on "-d","--domain DOMAIN" do |dom|
                @options[:domain] = dom
            end

            opts.on "-w","--warn WARN_DAYS",Integer do |w|
                @options[:warn_days]  = w.to_i
            end

            opts.on "-v","--verbose" do
                @options[:verbose] = true
            end
        end.parse!

    end

    #
    # Validates set options to rule out invalid values
    # e.g critical threshold > warning threshold
    #
    def validate_opts

        @opts_valid = true

        if @options[:domain].nil?
            @opts_error = "No domain name passed"
            @opts_valid = false
            return false
        end

        if @options[:crit_days] >= @options[:warn_days]
            @opts_error = "Critical threshold should be less than warning threshold"
            @opts_valid = false
            return false
        end

        return true
    end

    #
    # Performs actual WHOIS lookup
    #
    def whois_lookup(domain)
        begin
            @whois = Whois.whois(domain)
        rescue => e
            @whois = nil
            @whois_err = e.message
        end

        if @whois.kind_of? Whois::Record
            find_date
        end
    end

    #
    # Checks whether @whois record contains expiration time
    # information and sets some class variables accordingly
    #
    def find_date
        if @whois.expires_on.kind_of? Time
            @got_date = true
            #TODO: is this right way to do this?
            @expires_days = (@whois.expires_on.to_date - Date.today).to_i
        else
            @got_date = false
        end
    end

    #
    # returns true if check result is critical
    #
    def critical?
        return false unless @opts_valid && @got_date
        return @expires_days <= @options[:crit_days]
    end

    #
    # returns true if check result is a warning
    #
    def warning?
        return false unless @opts_valid && @got_date
        return @expires_days <= @options[:warn_days]
    end

    #
    # returns true if check result is OK
    #
    def ok?
        return false unless @opts_valid && @got_date
        return @expires_days > @options[:warn_days]
    end

    #
    # Displays messages which can indicate errors or
    # provide useful information (e.g when domain will
    # actually expire )
    #
    def message
        return "Invalid option(s) passed: #{@opts_error}" unless @opts_valid
        return "Unable to find expiration date in whois record" unless @got_date
        return "Unknown exception occured during whois lookup: #{@whois_error}" if @whois.nil?

        if @expires_days > 0
            "Domain expires in #{@expires_days} days"
        elsif @expires_days == 0
            "Domain expires today"
        else
            "Domain expired #{-@expires_days} ago"
        end
    end
end

Whois_Check.check
