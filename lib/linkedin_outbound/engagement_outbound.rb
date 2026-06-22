# frozen_string_literal: true

require "logger"

require_relative "apify_client"
require_relative "heyreach_client"

module LinkedinOutbound
  # Orchestrates a LinkedIn engagement -> outbound run:
  #
  #   1. Scrape engagers of a LinkedIn post via an Apify actor.
  #   2. Normalize them into HeyReach lead records.
  #   3. Push them into a HeyReach list (which can feed a campaign).
  #
  # Configuration is passed in explicitly so this class stays testable and so
  # secrets never need to live in the repo. See lib/tasks/linkedin_outbound.rake
  # for how it is wired up from ENV.
  class EngagementOutbound
    class Error < StandardError; end

    attr_reader :logger

    # config keys:
    #   :apify_actor   - Apify actor id, e.g. "apify~linkedin-post-reactions-scraper"
    #   :post_url      - LinkedIn post URL to pull engagement from
    #   :actor_input   - (optional) extra input merged into the actor payload
    #   :heyreach_list_id - HeyReach list id to add leads to
    #   :dry_run       - if true, scrape + map but do not push to HeyReach
    def initialize(config, apify: nil, heyreach: nil, logger: nil)
      @config = config
      @logger = logger || Logger.new($stdout)
      @logger.level = Logger::INFO
      @apify = apify || ApifyClient.new(logger: @logger)
      @heyreach = heyreach || HeyreachClient.new(logger: @logger)
    end

    def run
      validate!

      engagers = scrape_engagers
      leads = engagers.map { |e| to_heyreach_lead(e) }.compact
      leads = dedupe(leads)

      if leads.empty?
        logger.warn "No usable leads found (no profile URLs in the engagement data). Nothing to push."
        return { scraped: engagers.size, leads: 0, pushed: 0 }
      end

      if @config[:dry_run]
        logger.info "[dry-run] Would push #{leads.size} lead(s) to HeyReach list #{@config[:heyreach_list_id]}."
        return { scraped: engagers.size, leads: leads.size, pushed: 0, dry_run: true }
      end

      logger.info "Verifying HeyReach API key..."
      @heyreach.check_api_key

      @heyreach.add_leads_to_list(list_id: @config[:heyreach_list_id], leads: leads)
      logger.info "Done. Pushed #{leads.size} lead(s) to HeyReach list #{@config[:heyreach_list_id]}."

      { scraped: engagers.size, leads: leads.size, pushed: leads.size }
    end

    private

    def validate!
      missing = []
      missing << ":apify_actor" if blank?(@config[:apify_actor])
      missing << ":post_url" if blank?(@config[:post_url])
      missing << ":heyreach_list_id" if !@config[:dry_run] && blank?(@config[:heyreach_list_id])
      raise Error, "Missing required config: #{missing.join(', ')}" unless missing.empty?
    end

    def scrape_engagers
      input = { postUrl: @config[:post_url] }
      input.merge!(@config[:actor_input]) if @config[:actor_input].is_a?(Hash)
      @apify.run_and_fetch_items(actor: @config[:apify_actor], input: input)
    end

    # Maps a raw Apify engagement record to a HeyReach lead. Apify actors vary
    # in their field names, so we probe a set of common keys. A lead is only
    # usable if we can find a LinkedIn profile URL.
    def to_heyreach_lead(record)
      profile_url = dig_first(record, %w[profileUrl profile_url linkedinUrl linkedin_url url publicProfileUrl])
      return nil if blank?(profile_url)

      first = dig_first(record, %w[firstName first_name givenName])
      last  = dig_first(record, %w[lastName last_name familyName])
      full  = dig_first(record, %w[fullName name full_name])
      if blank?(first) && full
        parts = full.to_s.strip.split(/\s+/, 2)
        first = parts[0]
        last ||= parts[1]
      end

      lead = {
        "profileUrl" => profile_url.to_s.strip,
        "firstName" => first,
        "lastName" => last,
        "companyName" => dig_first(record, %w[companyName company company_name]),
        "position" => dig_first(record, %w[position title headline occupation]),
        "location" => dig_first(record, %w[location locationName]),
      }
      lead.reject! { |_, v| blank?(v) }
      lead
    end

    def dedupe(leads)
      leads.uniq { |l| l["profileUrl"].to_s.downcase.sub(%r{/+\z}, "") }
    end

    def dig_first(hash, keys)
      keys.each do |k|
        v = hash[k] || hash[k.to_sym]
        return v unless blank?(v)
      end
      nil
    end

    def blank?(val)
      val.nil? || val.to_s.strip.empty?
    end
  end
end
