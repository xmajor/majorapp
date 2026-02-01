class DailyStat < ActiveRecord::Base
  serialize :raw_data, JSON
  serialize :errors_data, JSON

  validates :date, presence: true, uniqueness: true

  scope :recent, -> { order(date: :desc) }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :this_week, -> { where(date: Date.current.beginning_of_week..Date.current) }
  scope :this_month, -> { where(date: Date.current.beginning_of_month..Date.current) }
  scope :last_30_days, -> { where(date: 30.days.ago.to_date..Date.current) }
  scope :unexported, -> { where(exported_to_sheets: false) }

  def self.from_aggregator(aggregator)
    stats = aggregator.to_hash

    find_or_initialize_by(date: stats[:date]).tap do |record|
      record.assign_attributes(
        ad_spend: stats[:ad_spend],
        link_cpc: stats[:link_cpc],
        link_ctr: stats[:link_ctr],
        cpm: stats[:cpm],
        impressions: stats[:impressions],
        unique_impressions: stats[:unique_impressions],
        clicks: stats[:clicks],
        fb_leads: stats[:fb_leads],
        hyros_leads: stats[:hyros_leads],
        total_leads: stats[:total_leads],
        qualified_leads: stats[:qualified_leads],
        cost_per_lead: stats[:cost_per_lead],
        booked_calls: stats[:booked_calls],
        completed_calls: stats[:completed_calls],
        cost_per_booked_call: stats[:cost_per_booked_call],
        call_show_rate: stats[:call_show_rate],
        page_views: stats[:page_views],
        unique_page_views: stats[:unique_page_views],
        opt_ins: stats[:opt_ins],
        form_submissions: stats[:form_submissions],
        form_completions: stats[:form_completions],
        completion_rate: stats[:completion_rate],
        application_submissions: stats[:application_submissions],
        attributed_revenue: stats[:attributed_revenue],
        roas: stats[:roas],
        raw_data: stats[:sources],
        errors_data: stats[:errors]
      )
      record.save!
    end
  end

  def mark_exported!
    update!(exported_to_sheets: true, last_exported_at: Time.current)
  end

  def has_errors?
    errors_data.present? && errors_data.any?
  end

  def summary
    {
      date: date,
      ad_spend: ad_spend,
      leads: total_leads,
      cpl: cost_per_lead,
      booked_calls: booked_calls,
      cpbc: cost_per_booked_call,
      applications: application_submissions,
      roas: roas
    }
  end

  def to_csv_row
    [
      date,
      ad_spend,
      link_cpc,
      link_ctr,
      cpm,
      cost_per_lead,
      cost_per_booked_call,
      unique_impressions,
      application_submissions,
      total_leads,
      booked_calls,
      page_views,
      form_completions,
      completion_rate
    ]
  end

  def self.csv_headers
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

  def self.weekly_summary
    this_week.group_by(&:date).transform_values do |records|
      records.first.summary
    end
  end

  def self.totals_for_range(start_date, end_date)
    stats = for_date_range(start_date, end_date)

    {
      total_ad_spend: stats.sum(:ad_spend),
      total_leads: stats.sum(:total_leads),
      total_booked_calls: stats.sum(:booked_calls),
      total_applications: stats.sum(:application_submissions),
      total_revenue: stats.sum(:attributed_revenue),
      avg_cpl: stats.average(:cost_per_lead)&.round(2) || 0,
      avg_cpbc: stats.average(:cost_per_booked_call)&.round(2) || 0,
      avg_roas: stats.average(:roas)&.round(2) || 0,
      days_count: stats.count
    }
  end
end
