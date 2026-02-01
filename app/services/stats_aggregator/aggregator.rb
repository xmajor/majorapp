module StatsAggregator
  class Aggregator
    attr_reader :date, :stats, :errors

    def initialize(date = Date.yesterday)
      @date = date
      @stats = {}
      @errors = []
      @logger = Rails.logger
    end

    def aggregate
      log_info("Starting daily stats aggregation for #{@date}")

      fetch_all_sources
      compile_metrics
      calculate_derived_metrics

      log_info("Aggregation complete. Errors: #{@errors.count}")

      self
    end

    def to_hash
      @compiled_stats || compile_metrics
    end

    def to_row
      stats = to_hash
      [
        stats[:date],
        stats[:ad_spend],
        stats[:link_cpc],
        stats[:link_ctr],
        stats[:cpm],
        stats[:cost_per_lead],
        stats[:cost_per_booked_call],
        stats[:unique_impressions],
        stats[:application_submissions],
        stats[:total_leads],
        stats[:booked_calls],
        stats[:page_views],
        stats[:form_completions],
        stats[:completion_rate]
      ]
    end

    def headers
      [
        'Date',
        'Ad Spend',
        'Link CPC',
        'Link CTR (%)',
        'CPM',
        'Cost Per Lead',
        'Cost Per Booked Call',
        'Unique Impressions',
        'Application Submissions',
        'Total Leads',
        'Booked Calls',
        'Page Views',
        'Form Completions',
        'Form Completion Rate (%)'
      ]
    end

    def success?
      @errors.empty?
    end

    private

    def fetch_all_sources
      fetch_facebook_stats
      fetch_clickfunnels_stats
      fetch_hyros_stats
      fetch_typeform_stats
    end

    def fetch_facebook_stats
      @stats[:facebook] = FacebookAdsClient.new.fetch_daily_stats(@date)
    rescue StandardError => e
      @errors << { source: 'facebook', error: e.message }
      @stats[:facebook] = empty_facebook_stats
    end

    def fetch_clickfunnels_stats
      @stats[:clickfunnels] = ClickFunnelsClient.new.fetch_daily_stats(@date)
    rescue StandardError => e
      @errors << { source: 'clickfunnels', error: e.message }
      @stats[:clickfunnels] = empty_clickfunnels_stats
    end

    def fetch_hyros_stats
      @stats[:hyros] = HyrosClient.new.fetch_daily_stats(@date)
    rescue StandardError => e
      @errors << { source: 'hyros', error: e.message }
      @stats[:hyros] = empty_hyros_stats
    end

    def fetch_typeform_stats
      @stats[:typeform] = TypeformClient.new.fetch_daily_stats(@date)
    rescue StandardError => e
      @errors << { source: 'typeform', error: e.message }
      @stats[:typeform] = empty_typeform_stats
    end

    def compile_metrics
      fb = @stats[:facebook] || {}
      cf = @stats[:clickfunnels] || {}
      hy = @stats[:hyros] || {}
      tf = @stats[:typeform] || {}

      @compiled_stats = {
        date: @date.to_s,
        aggregated_at: Time.current.iso8601,

        # Facebook Ads metrics
        ad_spend: fb[:ad_spend].to_f.round(2),
        link_cpc: fb[:link_cpc].to_f.round(2),
        link_ctr: fb[:link_ctr].to_f.round(2),
        cpm: fb[:cpm].to_f.round(2),
        impressions: fb[:impressions].to_i,
        unique_impressions: fb[:unique_impressions].to_i,
        clicks: fb[:clicks].to_i,

        # Lead metrics (combined from Facebook and Hyros)
        fb_leads: fb[:leads].to_i,
        hyros_leads: hy[:total_leads].to_i,
        total_leads: [fb[:leads].to_i, hy[:total_leads].to_i].max,
        qualified_leads: hy[:qualified_leads].to_i,

        # Cost metrics
        cost_per_lead: calculate_cost_per_lead(fb),
        cost_per_booked_call: hy[:cost_per_booked_call].to_f.round(2),

        # Call metrics (from Hyros)
        booked_calls: hy[:booked_calls].to_i,
        completed_calls: hy[:completed_calls].to_i,

        # ClickFunnels metrics
        page_views: cf[:page_views].to_i,
        unique_page_views: cf[:unique_page_views].to_i,
        opt_ins: cf[:opt_ins].to_i,
        pages_breakdown: cf[:pages_breakdown] || [],

        # Typeform metrics
        form_submissions: tf[:total_submissions].to_i,
        form_completions: tf[:total_completions].to_i,
        completion_rate: tf[:completion_rate].to_f.round(2),
        application_submissions: calculate_applications(hy, tf),
        forms_breakdown: tf[:forms_breakdown] || [],

        # Attribution data (from Hyros)
        attributed_revenue: hy[:attributed_revenue].to_f.round(2),

        # Raw data for debugging
        sources: {
          facebook: fb,
          clickfunnels: cf,
          hyros: hy,
          typeform: tf
        },

        errors: @errors
      }
    end

    def calculate_derived_metrics
      return unless @compiled_stats

      # Calculate ROAS if we have both spend and revenue
      if @compiled_stats[:ad_spend] > 0 && @compiled_stats[:attributed_revenue] > 0
        @compiled_stats[:roas] = (@compiled_stats[:attributed_revenue] / @compiled_stats[:ad_spend]).round(2)
      else
        @compiled_stats[:roas] = 0
      end

      # Calculate show rate for calls
      if @compiled_stats[:booked_calls] > 0
        @compiled_stats[:call_show_rate] = ((@compiled_stats[:completed_calls].to_f / @compiled_stats[:booked_calls]) * 100).round(2)
      else
        @compiled_stats[:call_show_rate] = 0
      end
    end

    def calculate_cost_per_lead(fb_stats)
      return fb_stats[:cost_per_lead].to_f.round(2) if fb_stats[:cost_per_lead].to_f > 0

      leads = [fb_stats[:leads].to_i, @stats.dig(:hyros, :total_leads).to_i].max
      return 0 if leads.zero?

      (fb_stats[:ad_spend].to_f / leads).round(2)
    end

    def calculate_applications(hyros_stats, typeform_stats)
      # Prefer Hyros application count, fallback to Typeform
      hyros_apps = hyros_stats[:application_submissions].to_i
      typeform_apps = typeform_stats[:application_submissions].to_i

      [hyros_apps, typeform_apps].max
    end

    def empty_facebook_stats
      { ad_spend: 0, link_cpc: 0, link_ctr: 0, cpm: 0, impressions: 0, unique_impressions: 0, clicks: 0, leads: 0, cost_per_lead: 0 }
    end

    def empty_clickfunnels_stats
      { page_views: 0, unique_page_views: 0, pages_breakdown: [], opt_ins: 0, new_contacts: 0 }
    end

    def empty_hyros_stats
      { attributed_revenue: 0, attributed_leads: 0, booked_calls: 0, completed_calls: 0, cost_per_booked_call: 0, total_leads: 0, qualified_leads: 0, application_submissions: 0 }
    end

    def empty_typeform_stats
      { total_submissions: 0, total_completions: 0, completion_rate: 0, forms_breakdown: [], application_submissions: 0 }
    end

    def log_info(message)
      @logger.info "[StatsAggregator] #{message}"
    end
  end
end
