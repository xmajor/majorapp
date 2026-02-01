namespace :stats do
  desc 'Aggregate daily stats from all sources (default: yesterday)'
  task :aggregate, [:date] => :environment do |_t, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.yesterday

    puts "[#{Time.current}] Starting stats aggregation for #{date}..."

    aggregator = StatsAggregator::Aggregator.new(date).aggregate

    if aggregator.success?
      puts "✓ Successfully aggregated stats from all sources"
    else
      puts "⚠ Aggregation completed with #{aggregator.errors.count} error(s):"
      aggregator.errors.each { |e| puts "  - #{e[:source]}: #{e[:error]}" }
    end

    # Save to database
    record = DailyStat.from_aggregator(aggregator)
    puts "✓ Saved stats to database (ID: #{record.id})"

    # Display summary
    stats = aggregator.to_hash
    puts "\n=== DAILY STATS SUMMARY (#{date}) ==="
    puts "Ad Spend: $#{'%.2f' % stats[:ad_spend]}"
    puts "Link CPC: $#{'%.2f' % stats[:link_cpc]}"
    puts "Link CTR: #{stats[:link_ctr]}%"
    puts "CPM: $#{'%.2f' % stats[:cpm]}"
    puts "Cost Per Lead: $#{'%.2f' % stats[:cost_per_lead]}"
    puts "Cost Per Booked Call: $#{'%.2f' % stats[:cost_per_booked_call]}"
    puts "Unique Impressions: #{stats[:unique_impressions]}"
    puts "Application Submissions: #{stats[:application_submissions]}"
    puts "Total Leads: #{stats[:total_leads]}"
    puts "Booked Calls: #{stats[:booked_calls]}"
    puts "================================="
  end

  desc 'Aggregate and export stats to CSV'
  task :export_csv, [:date] => :environment do |_t, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.yesterday

    puts "[#{Time.current}] Aggregating and exporting stats for #{date}..."

    aggregator = StatsAggregator::Aggregator.new(date).aggregate
    exporter = StatsAggregator::CsvExporter.new

    # Export standard CSV
    filepath = exporter.export(aggregator)
    puts "✓ Exported to: #{filepath}"

    # Export detailed report
    detailed_filepath = exporter.export_detailed(aggregator)
    puts "✓ Detailed report: #{detailed_filepath}"

    # Append to master file
    master_filepath = exporter.append_to_master(aggregator)
    puts "✓ Appended to master: #{master_filepath}"

    # Save to database
    DailyStat.from_aggregator(aggregator)
    puts "✓ Saved to database"
  end

  desc 'Aggregate and export stats to Google Sheets'
  task :export_sheets, [:date] => :environment do |_t, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.yesterday

    puts "[#{Time.current}] Aggregating and exporting stats for #{date} to Google Sheets..."

    aggregator = StatsAggregator::Aggregator.new(date).aggregate
    exporter = StatsAggregator::GoogleSheetsExporter.new

    url = exporter.export(aggregator)
    puts "✓ Exported to Google Sheets: #{url}"

    # Save to database and mark as exported
    record = DailyStat.from_aggregator(aggregator)
    record.mark_exported!
    puts "✓ Saved to database and marked as exported"
  end

  desc 'Run full daily aggregation (aggregate, save to DB, export to CSV and Sheets)'
  task :daily => :environment do
    date = Date.yesterday

    puts "[#{Time.current}] Running full daily stats aggregation for #{date}..."
    puts "=" * 60

    # Aggregate
    aggregator = StatsAggregator::Aggregator.new(date).aggregate

    # Save to database
    record = DailyStat.from_aggregator(aggregator)
    puts "✓ Saved to database"

    # Export to CSV
    csv_exporter = StatsAggregator::CsvExporter.new
    csv_exporter.export(aggregator)
    csv_exporter.append_to_master(aggregator)
    puts "✓ Exported to CSV"

    # Export to Google Sheets (if configured)
    if ENV['GOOGLE_SPREADSHEET_ID'].present?
      begin
        sheets_exporter = StatsAggregator::GoogleSheetsExporter.new
        sheets_exporter.export(aggregator)
        record.mark_exported!
        puts "✓ Exported to Google Sheets"
      rescue StandardError => e
        puts "⚠ Failed to export to Google Sheets: #{e.message}"
      end
    else
      puts "⚠ Google Sheets export skipped (GOOGLE_SPREADSHEET_ID not set)"
    end

    # Report summary
    stats = aggregator.to_hash
    puts "\n" + "=" * 60
    puts "DAILY STATS SUMMARY - #{date}"
    puts "=" * 60
    puts "Ad Spend:               $#{'%.2f' % stats[:ad_spend]}"
    puts "Link CPC:               $#{'%.2f' % stats[:link_cpc]}"
    puts "Link CTR:               #{stats[:link_ctr]}%"
    puts "CPM:                    $#{'%.2f' % stats[:cpm]}"
    puts "Cost Per Lead:          $#{'%.2f' % stats[:cost_per_lead]}"
    puts "Cost Per Booked Call:   $#{'%.2f' % stats[:cost_per_booked_call]}"
    puts "Unique Impressions:     #{stats[:unique_impressions]}"
    puts "Application Submissions: #{stats[:application_submissions]}"
    puts "Total Leads:            #{stats[:total_leads]}"
    puts "Booked Calls:           #{stats[:booked_calls]}"
    puts "ROAS:                   #{stats[:roas]}x"
    puts "=" * 60

    if aggregator.errors.any?
      puts "\nWARNINGS:"
      aggregator.errors.each { |e| puts "  - #{e[:source]}: #{e[:error]}" }
    end

    puts "\n[#{Time.current}] Daily aggregation complete!"
  end

  desc 'Backfill stats for a date range'
  task :backfill, [:start_date, :end_date] => :environment do |_t, args|
    start_date = Date.parse(args[:start_date])
    end_date = args[:end_date] ? Date.parse(args[:end_date]) : Date.yesterday

    puts "[#{Time.current}] Backfilling stats from #{start_date} to #{end_date}..."

    (start_date..end_date).each do |date|
      print "  Processing #{date}... "

      aggregator = StatsAggregator::Aggregator.new(date).aggregate
      DailyStat.from_aggregator(aggregator)

      status = aggregator.success? ? '✓' : "⚠ (#{aggregator.errors.count} errors)"
      puts status
    end

    puts "[#{Time.current}] Backfill complete!"
  end

  desc 'Export unexported stats to Google Sheets'
  task :export_pending => :environment do
    records = DailyStat.unexported.order(:date)

    if records.empty?
      puts "No unexported records found."
      exit
    end

    puts "Found #{records.count} unexported record(s). Exporting..."

    exporter = StatsAggregator::GoogleSheetsExporter.new

    records.each do |record|
      print "  Exporting #{record.date}... "

      aggregator = StatsAggregator::Aggregator.new(record.date)
      # Rebuild compiled stats from record
      aggregator.instance_variable_set(:@compiled_stats, record.attributes.symbolize_keys)

      exporter.export(aggregator)
      record.mark_exported!

      puts '✓'
    end

    puts "Export complete!"
  end

  desc 'Show stats summary for a date range'
  task :summary, [:start_date, :end_date] => :environment do |_t, args|
    start_date = args[:start_date] ? Date.parse(args[:start_date]) : 30.days.ago.to_date
    end_date = args[:end_date] ? Date.parse(args[:end_date]) : Date.yesterday

    totals = DailyStat.totals_for_range(start_date, end_date)

    puts "\n" + "=" * 60
    puts "STATS SUMMARY: #{start_date} to #{end_date} (#{totals[:days_count]} days)"
    puts "=" * 60
    puts "Total Ad Spend:         $#{'%.2f' % totals[:total_ad_spend]}"
    puts "Total Leads:            #{totals[:total_leads]}"
    puts "Total Booked Calls:     #{totals[:total_booked_calls]}"
    puts "Total Applications:     #{totals[:total_applications]}"
    puts "Total Revenue:          $#{'%.2f' % totals[:total_revenue]}"
    puts "-" * 60
    puts "Avg Cost Per Lead:      $#{'%.2f' % totals[:avg_cpl]}"
    puts "Avg Cost Per Booked Call: $#{'%.2f' % totals[:avg_cpbc]}"
    puts "Avg ROAS:               #{totals[:avg_roas]}x"
    puts "=" * 60
  end
end
