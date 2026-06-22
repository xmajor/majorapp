# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module LinkedinOutbound
  # Thin wrapper over the Apify API for running a LinkedIn engagement scraper
  # actor and collecting the resulting dataset items (the people who liked /
  # commented on a post, or otherwise engaged).
  #
  # Auth: an Apify API token, read from ENV["APIFY_TOKEN"]. The token is passed
  # as a query param per Apify's API. Never hard-code it.
  class ApifyClient
    DEFAULT_BASE = "https://api.apify.com/v2"

    class Error < StandardError; end

    def initialize(token: ENV["APIFY_TOKEN"], base_url: DEFAULT_BASE, logger: nil)
      raise Error, "APIFY_TOKEN is not set" if token.to_s.strip.empty?

      @token = token
      @base_url = base_url
      @logger = logger
    end

    # Runs an actor synchronously and returns the dataset items as an Array of
    # Hashes. `actor` is the actor id in the "user~actor-name" form (the tilde
    # form Apify uses in URLs), e.g. "apify~linkedin-post-reactions-scraper".
    #
    # `input` is the actor-specific input payload (e.g. { postUrl: "..." }).
    def run_and_fetch_items(actor:, input:, timeout_secs: 300)
      path = "/acts/#{actor}/run-sync-get-dataset-items"
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(token: @token, timeout: timeout_secs)

      log "Running Apify actor #{actor}..."
      body = post_json(uri, input, read_timeout: timeout_secs + 30)
      items = JSON.parse(body)
      raise Error, "Unexpected Apify response: #{items.inspect}" unless items.is_a?(Array)

      log "Apify returned #{items.size} engagement record(s)."
      items
    end

    # Runs a saved Apify task synchronously and returns its dataset items.
    # `task` is the task id or "user~task-name" form. `input` (optional) is
    # merged over the task's saved input on the Apify side.
    def run_task_and_fetch_items(task:, input: nil, timeout_secs: 600)
      path = "/actor-tasks/#{task}/run-sync-get-dataset-items"
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(token: @token, timeout: timeout_secs)

      log "Running Apify task #{task}..."
      body = post_json(uri, input || {}, read_timeout: timeout_secs + 30)
      items = JSON.parse(body)
      raise Error, "Unexpected Apify response: #{items.inspect}" unless items.is_a?(Array)

      log "Apify returned #{items.size} dataset record(s)."
      items
    end

    private

    def post_json(uri, payload, read_timeout:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = read_timeout

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(payload)

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        raise Error, "Apify request failed (#{res.code}): #{res.body}"
      end

      res.body
    end

    def log(msg)
      @logger&.info(msg)
    end
  end
end
