module StatsAggregator
  class FacebookAdsClient < BaseClient
    BASE_URL = 'https://graph.facebook.com/v18.0'

    def initialize
      super
      @access_token = ENV['FACEBOOK_ACCESS_TOKEN']
      @ad_account_id = ENV['FACEBOOK_AD_ACCOUNT_ID']
      validate_credentials!
    end

    def fetch_daily_stats(date = Date.yesterday)
      log_request('FacebookAds', "Fetching stats for #{date}")

      metrics = fetch_ad_insights(date)

      {
        date: date.to_s,
        source: 'facebook_ads',
        ad_spend: metrics[:spend].to_f,
        link_cpc: metrics[:cost_per_inline_link_click].to_f,
        link_ctr: metrics[:inline_link_click_ctr].to_f,
        cpm: metrics[:cpm].to_f,
        impressions: metrics[:impressions].to_i,
        unique_impressions: metrics[:reach].to_i,
        clicks: metrics[:inline_link_clicks].to_i,
        leads: metrics[:leads].to_i,
        cost_per_lead: calculate_cost_per_lead(metrics),
        raw_data: metrics
      }
    rescue StandardError => e
      log_error('FacebookAds', e)
      empty_stats(date, 'facebook_ads', e.message)
    end

    private

    def validate_credentials!
      raise AuthenticationError, 'FACEBOOK_ACCESS_TOKEN is required' if @access_token.blank?
      raise AuthenticationError, 'FACEBOOK_AD_ACCOUNT_ID is required' if @ad_account_id.blank?
    end

    def fetch_ad_insights(date)
      url = "#{BASE_URL}/act_#{@ad_account_id}/insights"

      options = {
        query: {
          access_token: @access_token,
          time_range: { since: date.to_s, until: date.to_s }.to_json,
          fields: insights_fields.join(','),
          level: 'account'
        }
      }

      response = request_with_retry(:get, url, options)
      parse_insights(response)
    end

    def insights_fields
      %w[
        spend
        impressions
        reach
        inline_link_clicks
        inline_link_click_ctr
        cost_per_inline_link_click
        cpm
        actions
        cost_per_action_type
      ]
    end

    def parse_insights(response)
      data = response.dig('data', 0) || {}

      leads = extract_action_value(data['actions'], 'lead')
      cost_per_lead = extract_action_value(data['cost_per_action_type'], 'lead')

      {
        spend: data['spend'],
        impressions: data['impressions'],
        reach: data['reach'],
        inline_link_clicks: data['inline_link_clicks'],
        inline_link_click_ctr: data['inline_link_click_ctr'],
        cost_per_inline_link_click: data['cost_per_inline_link_click'],
        cpm: data['cpm'],
        leads: leads,
        cost_per_lead: cost_per_lead
      }
    end

    def extract_action_value(actions, action_type)
      return 0 unless actions.is_a?(Array)
      action = actions.find { |a| a['action_type'] == action_type }
      action ? action['value'].to_f : 0
    end

    def calculate_cost_per_lead(metrics)
      return metrics[:cost_per_lead] if metrics[:cost_per_lead].to_f > 0
      return 0 if metrics[:leads].to_i == 0
      metrics[:spend].to_f / metrics[:leads].to_i
    end

    def empty_stats(date, source, error_message)
      {
        date: date.to_s,
        source: source,
        ad_spend: 0,
        link_cpc: 0,
        link_ctr: 0,
        cpm: 0,
        impressions: 0,
        unique_impressions: 0,
        clicks: 0,
        leads: 0,
        cost_per_lead: 0,
        error: error_message,
        raw_data: {}
      }
    end
  end
end
