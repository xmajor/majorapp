# frozen_string_literal: true

# Run a LinkedIn engagement -> outbound campaign.
#
# Scrapes the people who engaged with a LinkedIn post (via an Apify actor) and
# pushes them into a HeyReach list as leads.
#
# Required ENV:
#   APIFY_TOKEN        - Apify API token
#   HEYREACH_API_KEY   - HeyReach API key
#   APIFY_ACTOR        - Apify actor id, e.g. "apify~linkedin-post-reactions-scraper"
#   POST_URL           - LinkedIn post URL to pull engagement from
#   HEYREACH_LIST_ID   - HeyReach list id to add leads to (omit when DRY_RUN=1)
#
# Optional ENV:
#   DRY_RUN=1          - scrape + map but do not push to HeyReach
#   ACTOR_INPUT_JSON   - extra JSON merged into the Apify actor input
#
# Example:
#   APIFY_TOKEN=... HEYREACH_API_KEY=... \
#   APIFY_ACTOR=apify~linkedin-post-reactions-scraper \
#   POST_URL="https://www.linkedin.com/posts/..." \
#   HEYREACH_LIST_ID=12345 \
#   bundle exec rake linkedin_outbound:run

namespace :linkedin_outbound do
  desc "Scrape LinkedIn post engagers via Apify and push them to a HeyReach list"
  task :run do
    require_relative "../linkedin_outbound/engagement_outbound"

    actor_input =
      if ENV["ACTOR_INPUT_JSON"].to_s.strip.empty?
        {}
      else
        require "json"
        JSON.parse(ENV["ACTOR_INPUT_JSON"])
      end

    config = {
      apify_actor: ENV["APIFY_ACTOR"],
      post_url: ENV["POST_URL"],
      actor_input: actor_input,
      heyreach_list_id: ENV["HEYREACH_LIST_ID"],
      dry_run: ENV["DRY_RUN"] == "1",
    }

    result = LinkedinOutbound::EngagementOutbound.new(config).run
    puts "Result: #{result.inspect}"
  end
end
