# Backfills sent_contacts / failed_contacts for a WhatsApp campaign that ran before
# send tracking existed, from its saved Sidekiq log.
#
# Usage: bundle exec rake "campaigns:backfill_stats[CAMPAIGN_ID,/path/to/sidekiq.log]"
#   DRY_RUN=1                 print the counts without saving
#   DELIVERY_FAILURES=path    CSV "phone,error" of numbers Meta later reported as failed
#                             (status webhooks); those contacts move from sent to failed
namespace :campaigns do
  desc 'Backfill WhatsApp campaign send stats from a saved Sidekiq log'
  task :backfill_stats, [:campaign_id, :log_path] => :environment do |_, args|
    campaign = Campaign.find(args[:campaign_id])
    failures_path = ENV.fetch('DELIVERY_FAILURES', nil)
    failures = failures_path.present? ? Whatsapp::CampaignStatsBackfillService.read_delivery_failures(failures_path) : {}
    service = Whatsapp::CampaignStatsBackfillService.new(campaign: campaign, log_path: args[:log_path],
                                                         delivery_failures: failures)

    ActiveRecord::Base.transaction do
      counts = service.perform
      puts "Campaign #{campaign.id}: #{counts[:sent]} sent, #{counts[:failed]} failed"
      raise ActiveRecord::Rollback if ENV['DRY_RUN']
    end
  end
end
