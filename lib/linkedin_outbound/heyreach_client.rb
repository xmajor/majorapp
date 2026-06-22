# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module LinkedinOutbound
  # Thin wrapper over the HeyReach public API.
  #
  # Auth: an API key sent in the `X-API-KEY` header, read from
  # ENV["HEYREACH_API_KEY"]. Never hard-code it.
  #
  # Docs: https://documenter.getpostman.com/view/23808049/2sA2xb5F75
  class HeyreachClient
    DEFAULT_BASE = "https://api.heyreach.io/api/public"

    class Error < StandardError; end

    def initialize(api_key: ENV["HEYREACH_API_KEY"], base_url: DEFAULT_BASE, logger: nil)
      raise Error, "HEYREACH_API_KEY is not set" if api_key.to_s.strip.empty?

      @api_key = api_key
      @base_url = base_url
      @logger = logger
    end

    # Verifies the API key is valid. Returns true or raises.
    def check_api_key
      get("/auth/CheckApiKey")
      true
    end

    # Adds leads to an existing HeyReach list. `leads` is an Array of lead
    # Hashes (see EngagementOutbound#to_heyreach_lead for the shape).
    def add_leads_to_list(list_id:, leads:)
      payload = { listId: list_id, leads: leads }
      log "Adding #{leads.size} lead(s) to HeyReach list #{list_id}..."
      post("/list/AddLeadsToListV2", payload)
    end

    private

    def get(path)
      request(Net::HTTP::Get.new(URI("#{@base_url}#{path}")))
    end

    def post(path, payload)
      req = Net::HTTP::Post.new(URI("#{@base_url}#{path}"))
      req.body = JSON.generate(payload)
      request(req)
    end

    def request(req)
      uri = req.uri
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 120

      req["X-API-KEY"] = @api_key
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        raise Error, "HeyReach request failed (#{res.code}): #{res.body}"
      end

      res.body.to_s.empty? ? {} : JSON.parse(res.body)
    end

    def log(msg)
      @logger&.info(msg)
    end
  end
end
