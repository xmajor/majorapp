# Stats Aggregator Configuration
#
# This initializer loads the StatsAggregator module and validates
# that required environment variables are set.
#
# Required environment variables:
#
# Facebook Ads Manager:
#   FACEBOOK_ACCESS_TOKEN    - Facebook Marketing API access token
#   FACEBOOK_AD_ACCOUNT_ID   - Your Facebook Ad Account ID (without 'act_' prefix)
#
# ClickFunnels:
#   CLICKFUNNELS_API_KEY     - ClickFunnels API key
#   CLICKFUNNELS_WORKSPACE_ID - Your workspace ID
#
# Hyros:
#   HYROS_API_KEY            - Hyros API key
#
# Typeform:
#   TYPEFORM_ACCESS_TOKEN    - Typeform personal access token
#   TYPEFORM_FORM_IDS        - Comma-separated list of form IDs to track
#
# Google Sheets (optional):
#   GOOGLE_CREDENTIALS_PATH  - Path to Google service account JSON file
#   GOOGLE_SPREADSHEET_ID    - ID of the Google Spreadsheet to export to

module StatsAggregatorConfig
  class << self
    def validate!
      missing = []

      # Check Facebook credentials
      if facebook_enabled?
        missing << 'FACEBOOK_ACCESS_TOKEN' if ENV['FACEBOOK_ACCESS_TOKEN'].blank?
        missing << 'FACEBOOK_AD_ACCOUNT_ID' if ENV['FACEBOOK_AD_ACCOUNT_ID'].blank?
      end

      # Check ClickFunnels credentials
      if clickfunnels_enabled?
        missing << 'CLICKFUNNELS_API_KEY' if ENV['CLICKFUNNELS_API_KEY'].blank?
        missing << 'CLICKFUNNELS_WORKSPACE_ID' if ENV['CLICKFUNNELS_WORKSPACE_ID'].blank?
      end

      # Check Hyros credentials
      if hyros_enabled?
        missing << 'HYROS_API_KEY' if ENV['HYROS_API_KEY'].blank?
      end

      # Check Typeform credentials
      if typeform_enabled?
        missing << 'TYPEFORM_ACCESS_TOKEN' if ENV['TYPEFORM_ACCESS_TOKEN'].blank?
      end

      if missing.any?
        Rails.logger.warn "[StatsAggregator] Missing environment variables: #{missing.join(', ')}"
        Rails.logger.warn "[StatsAggregator] Some data sources will not be available."
      end

      missing
    end

    def facebook_enabled?
      ENV['STATS_FACEBOOK_ENABLED'] != 'false'
    end

    def clickfunnels_enabled?
      ENV['STATS_CLICKFUNNELS_ENABLED'] != 'false'
    end

    def hyros_enabled?
      ENV['STATS_HYROS_ENABLED'] != 'false'
    end

    def typeform_enabled?
      ENV['STATS_TYPEFORM_ENABLED'] != 'false'
    end

    def google_sheets_enabled?
      ENV['GOOGLE_SPREADSHEET_ID'].present? &&
        File.exist?(google_credentials_path)
    end

    def google_credentials_path
      ENV['GOOGLE_CREDENTIALS_PATH'] || Rails.root.join('config', 'google_credentials.json').to_s
    end

    def configured_sources
      sources = []
      sources << :facebook if facebook_enabled? && ENV['FACEBOOK_ACCESS_TOKEN'].present?
      sources << :clickfunnels if clickfunnels_enabled? && ENV['CLICKFUNNELS_API_KEY'].present?
      sources << :hyros if hyros_enabled? && ENV['HYROS_API_KEY'].present?
      sources << :typeform if typeform_enabled? && ENV['TYPEFORM_ACCESS_TOKEN'].present?
      sources
    end

    def status
      {
        facebook: {
          enabled: facebook_enabled?,
          configured: ENV['FACEBOOK_ACCESS_TOKEN'].present?
        },
        clickfunnels: {
          enabled: clickfunnels_enabled?,
          configured: ENV['CLICKFUNNELS_API_KEY'].present?
        },
        hyros: {
          enabled: hyros_enabled?,
          configured: ENV['HYROS_API_KEY'].present?
        },
        typeform: {
          enabled: typeform_enabled?,
          configured: ENV['TYPEFORM_ACCESS_TOKEN'].present?
        },
        google_sheets: {
          enabled: google_sheets_enabled?,
          spreadsheet_id: ENV['GOOGLE_SPREADSHEET_ID']
        }
      }
    end
  end
end

# Validate configuration on Rails startup (non-blocking)
Rails.application.config.after_initialize do
  StatsAggregatorConfig.validate!

  configured = StatsAggregatorConfig.configured_sources
  if configured.any?
    Rails.logger.info "[StatsAggregator] Configured sources: #{configured.join(', ')}"
  else
    Rails.logger.warn "[StatsAggregator] No data sources configured. Set environment variables to enable."
  end
end
