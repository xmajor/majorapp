class StatsController < ApplicationController
  before_action :set_date_range, only: [:index, :export]

  def index
    @stats = DailyStat.for_date_range(@start_date, @end_date).recent
    @totals = DailyStat.totals_for_range(@start_date, @end_date)
    @config_status = StatsAggregatorConfig.status
  end

  def show
    @date = params[:date] ? Date.parse(params[:date]) : Date.yesterday
    @stat = DailyStat.find_by(date: @date)

    if @stat.nil?
      flash[:notice] = "No stats found for #{@date}. Running aggregation..."
      redirect_to aggregate_stats_path(date: @date)
    end
  end

  def aggregate
    @date = params[:date] ? Date.parse(params[:date]) : Date.yesterday

    aggregator = StatsAggregator::Aggregator.new(@date).aggregate
    @stat = DailyStat.from_aggregator(aggregator)

    if aggregator.success?
      flash[:success] = "Successfully aggregated stats for #{@date}"
    else
      flash[:warning] = "Aggregation completed with #{aggregator.errors.count} error(s)"
    end

    redirect_to stat_path(date: @date)
  rescue StandardError => e
    flash[:error] = "Failed to aggregate stats: #{e.message}"
    redirect_to stats_path
  end

  def export
    @stats = DailyStat.for_date_range(@start_date, @end_date).order(:date)

    respond_to do |format|
      format.csv do
        send_data generate_csv(@stats),
                  filename: "daily_stats_#{@start_date}_to_#{@end_date}.csv",
                  type: 'text/csv'
      end
    end
  end

  def export_to_sheets
    @date = params[:date] ? Date.parse(params[:date]) : Date.yesterday

    aggregator = StatsAggregator::Aggregator.new(@date).aggregate
    exporter = StatsAggregator::GoogleSheetsExporter.new

    url = exporter.export(aggregator)
    DailyStat.from_aggregator(aggregator).mark_exported!

    flash[:success] = "Stats exported to Google Sheets"
    redirect_to url
  rescue StandardError => e
    flash[:error] = "Failed to export to Google Sheets: #{e.message}"
    redirect_to stats_path
  end

  def configuration
    @config_status = StatsAggregatorConfig.status
    @missing_vars = StatsAggregatorConfig.validate!
  end

  private

  def set_date_range
    @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.yesterday
  end

  def generate_csv(stats)
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << DailyStat.csv_headers
      stats.each { |stat| csv << stat.to_csv_row }
    end
  end
end
