module StatsAggregator
  class BaseClient
    include HTTParty

    class ApiError < StandardError; end
    class AuthenticationError < ApiError; end
    class RateLimitError < ApiError; end

    MAX_RETRIES = 3
    RETRY_DELAY = 2

    def initialize
      @logger = Rails.logger
    end

    protected

    def request_with_retry(method, url, options = {})
      retries = 0
      begin
        response = self.class.send(method, url, options)
        handle_response(response)
      rescue RateLimitError => e
        retries += 1
        if retries <= MAX_RETRIES
          sleep(RETRY_DELAY * retries)
          retry
        else
          raise e
        end
      end
    end

    def handle_response(response)
      case response.code
      when 200..299
        parse_response(response)
      when 401, 403
        raise AuthenticationError, "Authentication failed: #{response.message}"
      when 429
        raise RateLimitError, "Rate limit exceeded"
      else
        raise ApiError, "API error (#{response.code}): #{response.message}"
      end
    end

    def parse_response(response)
      return {} if response.body.nil? || response.body.empty?
      JSON.parse(response.body)
    rescue JSON::ParserError
      { raw: response.body }
    end

    def log_request(service, action)
      @logger.info "[StatsAggregator::#{service}] #{action}"
    end

    def log_error(service, error)
      @logger.error "[StatsAggregator::#{service}] Error: #{error.message}"
    end
  end
end
