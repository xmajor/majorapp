module StatsAggregator
  class HyrosClient < BaseClient
    BASE_URL = 'https://api.hyros.com/v1'

    def initialize
      super
      @api_key = ENV['HYROS_API_KEY']
      validate_credentials!
    end

    def fetch_daily_stats(date = Date.yesterday)
      log_request('Hyros', "Fetching stats for #{date}")

      attribution_data = fetch_attribution_data(date)
      calls_data = fetch_calls_data(date)
      leads_data = fetch_leads_data(date)

      {
        date: date.to_s,
        source: 'hyros',
        attributed_revenue: attribution_data[:revenue],
        attributed_leads: attribution_data[:leads],
        booked_calls: calls_data[:booked_calls],
        completed_calls: calls_data[:completed_calls],
        cost_per_booked_call: calls_data[:cost_per_booked_call],
        total_leads: leads_data[:total],
        qualified_leads: leads_data[:qualified],
        application_submissions: leads_data[:applications],
        raw_data: {
          attribution: attribution_data,
          calls: calls_data,
          leads: leads_data
        }
      }
    rescue StandardError => e
      log_error('Hyros', e)
      empty_stats(date, e.message)
    end

    def fetch_attribution_report(date_range_start, date_range_end)
      log_request('Hyros', "Fetching attribution report #{date_range_start} to #{date_range_end}")

      url = "#{BASE_URL}/reports/attribution"

      options = {
        headers: auth_headers,
        body: {
          start_date: date_range_start.to_s,
          end_date: date_range_end.to_s,
          group_by: 'source'
        }.to_json
      }

      response = request_with_retry(:post, url, options)
      parse_attribution_report(response)
    rescue StandardError => e
      log_error('Hyros', e)
      { error: e.message }
    end

    private

    def validate_credentials!
      raise AuthenticationError, 'HYROS_API_KEY is required' if @api_key.blank?
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def fetch_attribution_data(date)
      url = "#{BASE_URL}/attribution"

      options = {
        headers: auth_headers,
        query: {
          date: date.to_s
        }
      }

      response = request_with_retry(:get, url, options)
      parse_attribution_data(response)
    end

    def fetch_calls_data(date)
      url = "#{BASE_URL}/calls"

      options = {
        headers: auth_headers,
        query: {
          start_date: date.to_s,
          end_date: date.to_s
        }
      }

      response = request_with_retry(:get, url, options)
      parse_calls_data(response)
    end

    def fetch_leads_data(date)
      url = "#{BASE_URL}/leads"

      options = {
        headers: auth_headers,
        query: {
          created_at_start: date.beginning_of_day.iso8601,
          created_at_end: date.end_of_day.iso8601
        }
      }

      response = request_with_retry(:get, url, options)
      parse_leads_data(response)
    end

    def parse_attribution_data(response)
      data = response['data'] || {}

      {
        revenue: data['total_revenue'].to_f,
        leads: data['total_leads'].to_i,
        conversions: data['conversions'].to_i,
        sources: data['sources'] || []
      }
    end

    def parse_calls_data(response)
      data = response['data'] || {}
      calls = data['calls'] || []

      booked = calls.count { |c| c['status'] == 'booked' || c['status'] == 'scheduled' }
      completed = calls.count { |c| c['status'] == 'completed' || c['status'] == 'showed' }

      total_ad_spend = data['total_ad_spend'].to_f
      cost_per_call = booked > 0 ? (total_ad_spend / booked) : 0

      {
        booked_calls: booked,
        completed_calls: completed,
        total_calls: calls.count,
        cost_per_booked_call: cost_per_call.round(2),
        total_ad_spend: total_ad_spend
      }
    end

    def parse_leads_data(response)
      data = response['data'] || {}
      leads = data['leads'] || []

      applications = leads.count { |l| l['type'] == 'application' || l['source'] == 'application' }
      qualified = leads.count { |l| l['qualified'] == true }

      {
        total: leads.count,
        qualified: qualified,
        applications: applications,
        leads_list: leads.map { |l| { id: l['id'], email: l['email'], source: l['source'] } }
      }
    end

    def parse_attribution_report(response)
      data = response['data'] || []

      data.map do |source|
        {
          source_name: source['source_name'],
          revenue: source['revenue'].to_f,
          leads: source['leads'].to_i,
          roas: source['roas'].to_f,
          cost: source['cost'].to_f
        }
      end
    end

    def empty_stats(date, error_message)
      {
        date: date.to_s,
        source: 'hyros',
        attributed_revenue: 0,
        attributed_leads: 0,
        booked_calls: 0,
        completed_calls: 0,
        cost_per_booked_call: 0,
        total_leads: 0,
        qualified_leads: 0,
        application_submissions: 0,
        error: error_message,
        raw_data: {}
      }
    end
  end
end
