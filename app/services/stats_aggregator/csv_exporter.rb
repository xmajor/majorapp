require 'csv'

module StatsAggregator
  class CsvExporter
    DEFAULT_EXPORT_PATH = Rails.root.join('tmp', 'exports')

    def initialize(options = {})
      @export_path = options[:path] || DEFAULT_EXPORT_PATH
      @logger = Rails.logger
      ensure_export_directory
    end

    def export(aggregator)
      filename = generate_filename(aggregator.date)
      filepath = File.join(@export_path, filename)

      CSV.open(filepath, 'wb') do |csv|
        csv << aggregator.headers
        csv << aggregator.to_row
      end

      log_info("Exported daily stats to #{filepath}")
      filepath
    end

    def export_range(start_date, end_date, filename = nil)
      filename ||= "stats_#{start_date}_to_#{end_date}.csv"
      filepath = File.join(@export_path, filename)

      aggregators = (start_date..end_date).map do |date|
        Aggregator.new(date).aggregate
      end

      CSV.open(filepath, 'wb') do |csv|
        csv << aggregators.first.headers
        aggregators.each { |agg| csv << agg.to_row }
      end

      log_info("Exported stats range to #{filepath}")
      filepath
    end

    def append_to_master(aggregator, master_filename = 'daily_stats_master.csv')
      filepath = File.join(@export_path, master_filename)
      file_exists = File.exist?(filepath)

      CSV.open(filepath, 'ab') do |csv|
        csv << aggregator.headers unless file_exists
        csv << aggregator.to_row
      end

      log_info("Appended daily stats to #{filepath}")
      filepath
    end

    def export_detailed(aggregator)
      filename = generate_filename(aggregator.date, 'detailed')
      filepath = File.join(@export_path, filename)

      stats = aggregator.to_hash

      CSV.open(filepath, 'wb') do |csv|
        # Main metrics section
        csv << ['=== DAILY STATS REPORT ===']
        csv << ['Date', stats[:date]]
        csv << ['Generated At', stats[:aggregated_at]]
        csv << []

        # Ad Performance
        csv << ['=== AD PERFORMANCE ===']
        csv << ['Metric', 'Value']
        csv << ['Ad Spend', format_currency(stats[:ad_spend])]
        csv << ['Link CPC', format_currency(stats[:link_cpc])]
        csv << ['Link CTR', "#{stats[:link_ctr]}%"]
        csv << ['CPM', format_currency(stats[:cpm])]
        csv << ['Impressions', stats[:impressions]]
        csv << ['Unique Impressions', stats[:unique_impressions]]
        csv << ['Clicks', stats[:clicks]]
        csv << []

        # Lead Metrics
        csv << ['=== LEAD METRICS ===']
        csv << ['Metric', 'Value']
        csv << ['Total Leads', stats[:total_leads]]
        csv << ['Qualified Leads', stats[:qualified_leads]]
        csv << ['Cost Per Lead', format_currency(stats[:cost_per_lead])]
        csv << ['Application Submissions', stats[:application_submissions]]
        csv << []

        # Call Metrics
        csv << ['=== CALL METRICS ===']
        csv << ['Metric', 'Value']
        csv << ['Booked Calls', stats[:booked_calls]]
        csv << ['Completed Calls', stats[:completed_calls]]
        csv << ['Cost Per Booked Call', format_currency(stats[:cost_per_booked_call])]
        csv << ['Call Show Rate', "#{stats[:call_show_rate]}%"]
        csv << []

        # Page Metrics
        csv << ['=== PAGE METRICS ===']
        csv << ['Metric', 'Value']
        csv << ['Page Views', stats[:page_views]]
        csv << ['Unique Page Views', stats[:unique_page_views]]
        csv << ['Opt-ins', stats[:opt_ins]]
        csv << []

        # Pages breakdown
        if stats[:pages_breakdown].any?
          csv << ['=== PAGES BREAKDOWN ===']
          csv << ['Page Name', 'Views', 'Unique Views', 'Conversions']
          stats[:pages_breakdown].each do |page|
            csv << [page[:name], page[:views], page[:unique_views], page[:conversions]]
          end
          csv << []
        end

        # Form Metrics
        csv << ['=== FORM METRICS ===']
        csv << ['Metric', 'Value']
        csv << ['Form Submissions', stats[:form_submissions]]
        csv << ['Form Completions', stats[:form_completions]]
        csv << ['Completion Rate', "#{stats[:completion_rate]}%"]
        csv << []

        # Forms breakdown
        if stats[:forms_breakdown].any?
          csv << ['=== FORMS BREAKDOWN ===']
          csv << ['Form Title', 'Submissions', 'Completions']
          stats[:forms_breakdown].each do |form|
            csv << [form[:form_title], form[:submissions], form[:completions]]
          end
          csv << []
        end

        # Revenue & ROI
        csv << ['=== REVENUE & ROI ===']
        csv << ['Metric', 'Value']
        csv << ['Attributed Revenue', format_currency(stats[:attributed_revenue])]
        csv << ['ROAS', "#{stats[:roas]}x"]
        csv << []

        # Errors (if any)
        if stats[:errors].any?
          csv << ['=== ERRORS ===']
          csv << ['Source', 'Error']
          stats[:errors].each do |error|
            csv << [error[:source], error[:error]]
          end
        end
      end

      log_info("Exported detailed stats to #{filepath}")
      filepath
    end

    private

    def ensure_export_directory
      FileUtils.mkdir_p(@export_path) unless File.directory?(@export_path)
    end

    def generate_filename(date, suffix = nil)
      base = "daily_stats_#{date}"
      suffix ? "#{base}_#{suffix}.csv" : "#{base}.csv"
    end

    def format_currency(amount)
      "$#{'%.2f' % amount}"
    end

    def log_info(message)
      @logger.info "[StatsAggregator::CsvExporter] #{message}"
    end
  end
end
