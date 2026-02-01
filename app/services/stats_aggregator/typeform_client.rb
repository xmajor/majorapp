module StatsAggregator
  class TypeformClient < BaseClient
    BASE_URL = 'https://api.typeform.com'

    def initialize
      super
      @access_token = ENV['TYPEFORM_ACCESS_TOKEN']
      @form_ids = (ENV['TYPEFORM_FORM_IDS'] || '').split(',').map(&:strip)
      validate_credentials!
    end

    def fetch_daily_stats(date = Date.yesterday)
      log_request('Typeform', "Fetching stats for #{date}")

      forms_data = @form_ids.map { |form_id| fetch_form_responses(form_id, date) }

      total_submissions = forms_data.sum { |f| f[:submissions] }
      total_completions = forms_data.sum { |f| f[:completions] }

      {
        date: date.to_s,
        source: 'typeform',
        total_submissions: total_submissions,
        total_completions: total_completions,
        completion_rate: calculate_completion_rate(total_submissions, total_completions),
        forms_breakdown: forms_data,
        application_submissions: count_applications(forms_data),
        raw_data: { forms: forms_data }
      }
    rescue StandardError => e
      log_error('Typeform', e)
      empty_stats(date, e.message)
    end

    def fetch_form_responses(form_id, date = Date.yesterday)
      log_request('Typeform', "Fetching form #{form_id} responses for #{date}")

      responses = fetch_responses(form_id, date)
      form_info = fetch_form_info(form_id)

      {
        form_id: form_id,
        form_title: form_info[:title],
        submissions: responses[:total_items],
        completions: responses[:completed],
        partial: responses[:partial],
        responses: responses[:items]
      }
    rescue StandardError => e
      log_error('Typeform', e)
      {
        form_id: form_id,
        form_title: 'Unknown',
        submissions: 0,
        completions: 0,
        partial: 0,
        responses: [],
        error: e.message
      }
    end

    private

    def validate_credentials!
      raise AuthenticationError, 'TYPEFORM_ACCESS_TOKEN is required' if @access_token.blank?
      Rails.logger.warn '[StatsAggregator::Typeform] No form IDs configured' if @form_ids.empty?
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{@access_token}",
        'Content-Type' => 'application/json'
      }
    end

    def fetch_responses(form_id, date)
      url = "#{BASE_URL}/forms/#{form_id}/responses"

      options = {
        headers: auth_headers,
        query: {
          since: date.beginning_of_day.iso8601,
          until: date.end_of_day.iso8601,
          page_size: 1000,
          completed: true
        }
      }

      # First fetch completed responses
      completed_response = request_with_retry(:get, url, options)
      completed_count = completed_response['total_items'] || 0
      completed_items = completed_response['items'] || []

      # Then fetch all responses (including partial)
      options[:query][:completed] = nil
      all_response = request_with_retry(:get, url, options)
      total_count = all_response['total_items'] || 0

      {
        total_items: total_count,
        completed: completed_count,
        partial: total_count - completed_count,
        items: parse_responses(completed_items)
      }
    end

    def fetch_form_info(form_id)
      url = "#{BASE_URL}/forms/#{form_id}"

      options = {
        headers: auth_headers
      }

      response = request_with_retry(:get, url, options)

      {
        id: response['id'],
        title: response['title'] || 'Untitled Form',
        fields_count: (response['fields'] || []).count
      }
    end

    def parse_responses(items)
      items.map do |item|
        {
          response_id: item['response_id'],
          submitted_at: item['submitted_at'],
          landed_at: item['landed_at'],
          answers_count: (item['answers'] || []).count,
          metadata: {
            user_agent: item.dig('metadata', 'user_agent'),
            platform: item.dig('metadata', 'platform'),
            referer: item.dig('metadata', 'referer')
          }
        }
      end
    end

    def calculate_completion_rate(submissions, completions)
      return 0 if submissions.zero?
      ((completions.to_f / submissions) * 100).round(2)
    end

    def count_applications(forms_data)
      # Count submissions from forms that have 'application' in their title
      # or are explicitly marked as application forms
      application_forms = forms_data.select do |form|
        form[:form_title].to_s.downcase.include?('application') ||
        form[:form_id].to_s.downcase.include?('application')
      end

      application_forms.sum { |f| f[:completions] }
    end

    def empty_stats(date, error_message)
      {
        date: date.to_s,
        source: 'typeform',
        total_submissions: 0,
        total_completions: 0,
        completion_rate: 0,
        forms_breakdown: [],
        application_submissions: 0,
        error: error_message,
        raw_data: {}
      }
    end
  end
end
