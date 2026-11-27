# Backfills sent_contacts / failed_contacts for a WhatsApp campaign that ran before
# send tracking existed, by replaying the OneoffCampaignService log lines.
#
# Usage: bundle exec rake "campaigns:backfill_stats[CAMPAIGN_ID,/path/to/sidekiq.log]"
#   DRY_RUN=1                 print the counts without saving
#   DELIVERY_FAILURES=path    CSV "phone,error" of numbers Meta later reported as failed
#                             (status webhooks); those contacts move from sent to failed
namespace :campaigns do
  desc 'Backfill WhatsApp campaign send stats from a saved Sidekiq log'
  task :backfill_stats, [:campaign_id, :log_path] => :environment do |_, args|
    campaign = Campaign.find(args[:campaign_id])
    contacts_by_phone = campaign.account.contacts.where.not(phone_number: nil).index_by(&:phone_number)
    delivery_failures = {}
    if ENV['DELIVERY_FAILURES'].present?
      File.foreach(ENV['DELIVERY_FAILURES']) do |line|
        phone, error = line.strip.split(',', 2)
        delivery_failures[phone] = error.presence || 'delivery failed' if phone&.start_with?('+')
      end
    end

    results = {}
    current = nil

    # Only lines written by the campaign job count; webhook payloads in the same log are ignored
    File.foreach(args[:log_path]) do |line|
      if (match = line.match(/Processing contact: .* \((\+\d+)\)/))
        current = match[1]
        results[current] ||= nil
      elsif current && line.include?('Skipping contact')
        results[current] = 'skipped'
      elsif (match = line.match(/Failed to send WhatsApp template message to (\+\d+)/))
        results[match[1]] = 'send failed'
      end
    end

    sent = []
    failed = []
    results.each do |phone, error|
      contact = contacts_by_phone[phone]
      entry = { id: contact&.id, name: contact&.name, phone: phone }
      error ||= delivery_failures[phone]
      error ? failed << entry.merge(error: error) : sent << entry
    end

    puts "Campaign #{campaign.id}: #{sent.size} sent, #{failed.size} failed"
    campaign.update_columns(sent_contacts: sent, failed_contacts: failed) unless ENV['DRY_RUN']
  end
end
