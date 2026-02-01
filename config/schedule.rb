# Use this file to easily define all of your cron jobs.
#
# Learn more: http://github.com/javan/whenever
#
# To update your crontab, run:
#   whenever --update-crontab
#
# To see the generated crontab without updating, run:
#   whenever

# Set the environment
set :environment, ENV['RAILS_ENV'] || 'production'

# Set the output log file
set :output, { error: 'log/cron_error.log', standard: 'log/cron.log' }

# Set the path to your application
set :path, '/home/user/majorapp'

# ==================================
# Daily Stats Aggregation Schedule
# ==================================

# Run the full daily stats aggregation every day at 6:00 AM
# This runs after midnight to ensure all data from the previous day is available
every 1.day, at: '6:00 am' do
  rake 'stats:daily'
end

# Alternative: Run at multiple times if you want more frequent updates
# every 1.day, at: ['6:00 am', '12:00 pm', '6:00 pm'] do
#   rake 'stats:aggregate'
# end

# ==================================
# Weekly Summary Email (Optional)
# ==================================

# Generate a weekly summary every Monday at 8:00 AM
every :monday, at: '8:00 am' do
  rake 'stats:summary[7.days.ago, yesterday]'
end

# ==================================
# Cleanup and Maintenance
# ==================================

# Export any pending stats to Google Sheets every hour
# (in case the daily export failed)
every 1.hour do
  rake 'stats:export_pending'
end

# ==================================
# Development/Testing Helpers
# ==================================

# For testing, you can run every minute (uncomment only for testing!)
# every 1.minute do
#   rake 'stats:aggregate'
# end
