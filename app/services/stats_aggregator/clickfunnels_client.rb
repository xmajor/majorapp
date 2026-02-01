module StatsAggregator
  class ClickFunnelsClient < BaseClient
    BASE_URL = 'https://api.clickfunnels.com/api/v2'

    def initialize
      super
      @api_key = ENV['CLICKFUNNELS_API_KEY']
      @workspace_id = ENV['CLICKFUNNELS_WORKSPACE_ID']
      validate_credentials!
    end

    def fetch_daily_stats(date = Date.yesterday)
      log_request('ClickFunnels', "Fetching stats for #{date}")

      pages_data = fetch_pages_analytics(date)
      contacts_data = fetch_contacts(date)

      {
        date: date.to_s,
        source: 'clickfunnels',
        page_views: pages_data[:total_views],
        unique_page_views: pages_data[:unique_views],
        pages_breakdown: pages_data[:pages],
        opt_ins: contacts_data[:opt_ins],
        new_contacts: contacts_data[:new_contacts],
        raw_data: { pages: pages_data, contacts: contacts_data }
      }
    rescue StandardError => e
      log_error('ClickFunnels', e)
      empty_stats(date, e.message)
    end

    def fetch_funnel_stats(funnel_id, date = Date.yesterday)
      log_request('ClickFunnels', "Fetching funnel #{funnel_id} stats for #{date}")

      url = "#{BASE_URL}/workspaces/#{@workspace_id}/funnels/#{funnel_id}/analytics"

      options = {
        headers: auth_headers,
        query: {
          start_date: date.to_s,
          end_date: date.to_s
        }
      }

      response = request_with_retry(:get, url, options)
      parse_funnel_analytics(response, date)
    rescue StandardError => e
      log_error('ClickFunnels', e)
      { error: e.message }
    end

    private

    def validate_credentials!
      raise AuthenticationError, 'CLICKFUNNELS_API_KEY is required' if @api_key.blank?
      raise AuthenticationError, 'CLICKFUNNELS_WORKSPACE_ID is required' if @workspace_id.blank?
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def fetch_pages_analytics(date)
      url = "#{BASE_URL}/workspaces/#{@workspace_id}/pages"

      options = {
        headers: auth_headers,
        query: {
          updated_after: date.beginning_of_day.iso8601,
          updated_before: date.end_of_day.iso8601
        }
      }

      response = request_with_retry(:get, url, options)
      parse_pages_response(response)
    end

    def fetch_contacts(date)
      url = "#{BASE_URL}/workspaces/#{@workspace_id}/contacts"

      options = {
        headers: auth_headers,
        query: {
          created_after: date.beginning_of_day.iso8601,
          created_before: date.end_of_day.iso8601
        }
      }

      response = request_with_retry(:get, url, options)
      parse_contacts_response(response)
    end

    def parse_pages_response(response)
      pages = response['data'] || []

      pages_breakdown = pages.map do |page|
        {
          id: page['id'],
          name: page['attributes']['name'],
          views: page.dig('attributes', 'page_views') || 0,
          unique_views: page.dig('attributes', 'unique_page_views') || 0,
          conversions: page.dig('attributes', 'conversions') || 0
        }
      end

      {
        total_views: pages_breakdown.sum { |p| p[:views].to_i },
        unique_views: pages_breakdown.sum { |p| p[:unique_views].to_i },
        pages: pages_breakdown
      }
    end

    def parse_contacts_response(response)
      contacts = response['data'] || []

      opt_ins = contacts.count { |c| c.dig('attributes', 'opted_in') }

      {
        new_contacts: contacts.count,
        opt_ins: opt_ins
      }
    end

    def parse_funnel_analytics(response, date)
      data = response['data'] || {}

      {
        date: date.to_s,
        page_views: data['page_views'] || 0,
        unique_visitors: data['unique_visitors'] || 0,
        opt_ins: data['opt_ins'] || 0,
        sales: data['sales'] || 0,
        revenue: data['revenue'] || 0
      }
    end

    def empty_stats(date, error_message)
      {
        date: date.to_s,
        source: 'clickfunnels',
        page_views: 0,
        unique_page_views: 0,
        pages_breakdown: [],
        opt_ins: 0,
        new_contacts: 0,
        error: error_message,
        raw_data: {}
      }
    end
  end
end
