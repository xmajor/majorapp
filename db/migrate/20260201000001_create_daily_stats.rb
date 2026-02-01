class CreateDailyStats < ActiveRecord::Migration
  def change
    create_table :daily_stats do |t|
      t.date :date, null: false, index: { unique: true }

      # Facebook Ads metrics
      t.decimal :ad_spend, precision: 10, scale: 2, default: 0
      t.decimal :link_cpc, precision: 10, scale: 4, default: 0
      t.decimal :link_ctr, precision: 10, scale: 4, default: 0
      t.decimal :cpm, precision: 10, scale: 4, default: 0
      t.integer :impressions, default: 0
      t.integer :unique_impressions, default: 0
      t.integer :clicks, default: 0

      # Lead metrics
      t.integer :fb_leads, default: 0
      t.integer :hyros_leads, default: 0
      t.integer :total_leads, default: 0
      t.integer :qualified_leads, default: 0
      t.decimal :cost_per_lead, precision: 10, scale: 2, default: 0

      # Call metrics (Hyros)
      t.integer :booked_calls, default: 0
      t.integer :completed_calls, default: 0
      t.decimal :cost_per_booked_call, precision: 10, scale: 2, default: 0
      t.decimal :call_show_rate, precision: 5, scale: 2, default: 0

      # ClickFunnels metrics
      t.integer :page_views, default: 0
      t.integer :unique_page_views, default: 0
      t.integer :opt_ins, default: 0

      # Typeform metrics
      t.integer :form_submissions, default: 0
      t.integer :form_completions, default: 0
      t.decimal :completion_rate, precision: 5, scale: 2, default: 0
      t.integer :application_submissions, default: 0

      # Revenue & ROI
      t.decimal :attributed_revenue, precision: 12, scale: 2, default: 0
      t.decimal :roas, precision: 10, scale: 2, default: 0

      # Raw data storage (JSON)
      t.text :raw_data
      t.text :errors_data

      # Export tracking
      t.boolean :exported_to_sheets, default: false
      t.datetime :last_exported_at

      t.timestamps null: false
    end

    add_index :daily_stats, :created_at
    add_index :daily_stats, :exported_to_sheets
  end
end
