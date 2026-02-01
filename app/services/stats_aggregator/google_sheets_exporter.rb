module StatsAggregator
  class GoogleSheetsExporter
    SCOPES = [
      'https://www.googleapis.com/auth/drive',
      'https://www.googleapis.com/auth/spreadsheets'
    ].freeze

    def initialize
      @logger = Rails.logger
      @credentials_path = ENV['GOOGLE_CREDENTIALS_PATH'] || Rails.root.join('config', 'google_credentials.json')
      @spreadsheet_id = ENV['GOOGLE_SPREADSHEET_ID']
      @session = nil
    end

    def export(aggregator, sheet_name = 'Daily Stats')
      ensure_session!
      ensure_spreadsheet!

      worksheet = find_or_create_worksheet(sheet_name)
      append_row(worksheet, aggregator)

      log_info("Exported stats for #{aggregator.date} to Google Sheets")
      spreadsheet_url
    rescue StandardError => e
      log_error("Failed to export to Google Sheets: #{e.message}")
      raise
    end

    def export_range(start_date, end_date, sheet_name = 'Daily Stats')
      ensure_session!
      ensure_spreadsheet!

      worksheet = find_or_create_worksheet(sheet_name)

      (start_date..end_date).each do |date|
        aggregator = Aggregator.new(date).aggregate
        append_row(worksheet, aggregator)
      end

      log_info("Exported stats from #{start_date} to #{end_date} to Google Sheets")
      spreadsheet_url
    rescue StandardError => e
      log_error("Failed to export range to Google Sheets: #{e.message}")
      raise
    end

    def create_new_spreadsheet(title = "Daily Stats - #{Date.current}")
      ensure_session!

      spreadsheet = @session.create_spreadsheet(title)
      @spreadsheet = spreadsheet
      @spreadsheet_id = spreadsheet.key

      log_info("Created new spreadsheet: #{title} (#{@spreadsheet_id})")

      # Set up the default worksheet with headers
      worksheet = spreadsheet.worksheets.first
      setup_headers(worksheet)

      {
        spreadsheet_id: @spreadsheet_id,
        url: spreadsheet_url,
        title: title
      }
    end

    def spreadsheet_url
      "https://docs.google.com/spreadsheets/d/#{@spreadsheet_id}"
    end

    private

    def ensure_session!
      return if @session

      unless File.exist?(@credentials_path)
        raise ConfigurationError, "Google credentials file not found at #{@credentials_path}. " \
          "Please download your service account credentials from Google Cloud Console."
      end

      @session = GoogleDrive::Session.from_service_account_key(@credentials_path)
      log_info("Google Drive session initialized")
    end

    def ensure_spreadsheet!
      return if @spreadsheet

      if @spreadsheet_id.blank?
        raise ConfigurationError, "GOOGLE_SPREADSHEET_ID environment variable not set. " \
          "Either set it or use create_new_spreadsheet to create one."
      end

      @spreadsheet = @session.spreadsheet_by_key(@spreadsheet_id)
      log_info("Connected to spreadsheet: #{@spreadsheet.title}")
    end

    def find_or_create_worksheet(sheet_name)
      worksheet = @spreadsheet.worksheet_by_title(sheet_name)

      unless worksheet
        worksheet = @spreadsheet.add_worksheet(sheet_name, 1000, 20)
        setup_headers(worksheet)
        log_info("Created new worksheet: #{sheet_name}")
      end

      worksheet
    end

    def setup_headers(worksheet)
      headers = Aggregator.new.headers
      headers.each_with_index do |header, index|
        worksheet[1, index + 1] = header
      end
      worksheet.save
    end

    def append_row(worksheet, aggregator)
      # Find the next empty row
      next_row = find_next_empty_row(worksheet)

      # Check if this date already exists (to avoid duplicates)
      if date_exists?(worksheet, aggregator.date)
        log_info("Stats for #{aggregator.date} already exist, updating instead")
        update_existing_row(worksheet, aggregator)
        return
      end

      # Write the row
      row_data = aggregator.to_row
      row_data.each_with_index do |value, index|
        worksheet[next_row, index + 1] = value
      end

      worksheet.save
      log_info("Appended row #{next_row} for date #{aggregator.date}")
    end

    def find_next_empty_row(worksheet)
      # Start from row 2 (after headers) and find first empty row
      row = 2
      while worksheet[row, 1].present?
        row += 1
      end
      row
    end

    def date_exists?(worksheet, date)
      row = 2
      while worksheet[row, 1].present?
        return true if worksheet[row, 1] == date.to_s
        row += 1
      end
      false
    end

    def update_existing_row(worksheet, aggregator)
      row = find_row_by_date(worksheet, aggregator.date)
      return unless row

      row_data = aggregator.to_row
      row_data.each_with_index do |value, index|
        worksheet[row, index + 1] = value
      end

      worksheet.save
      log_info("Updated row #{row} for date #{aggregator.date}")
    end

    def find_row_by_date(worksheet, date)
      row = 2
      while worksheet[row, 1].present?
        return row if worksheet[row, 1] == date.to_s
        row += 1
      end
      nil
    end

    def log_info(message)
      @logger.info "[StatsAggregator::GoogleSheetsExporter] #{message}"
    end

    def log_error(message)
      @logger.error "[StatsAggregator::GoogleSheetsExporter] #{message}"
    end

    class ConfigurationError < StandardError; end
  end
end
