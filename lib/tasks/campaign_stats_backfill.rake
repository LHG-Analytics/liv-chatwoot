# Backfills sent_contacts / failed_contacts for a WhatsApp campaign that ran before
# send tracking existed, by replaying the OneoffCampaignService log lines.
#
# Usage: bundle exec rake "campaigns:backfill_stats[CAMPAIGN_ID,/path/to/sidekiq.log]"
# Add DRY_RUN=1 to print the counts without saving.
namespace :campaigns do
  desc 'Backfill WhatsApp campaign send stats from a saved Sidekiq log'
  task :backfill_stats, [:campaign_id, :log_path] => :environment do |_, args|
    campaign = Campaign.find(args[:campaign_id])
    contacts_by_phone = campaign.account.contacts.where.not(phone_number: nil).index_by(&:phone_number)

    sent = []
    failed = []
    current = nil

    finish = lambda do
      next if current.nil?

      contact = contacts_by_phone[current[:phone]]
      entry = { id: contact&.id, name: contact&.name, phone: current[:phone] }
      current[:error] ? failed << entry.merge(error: current[:error]) : sent << entry
      current = nil
    end

    File.foreach(args[:log_path]) do |line|
      if (match = line.match(/Processing contact: .* \((\+\d+)\)/))
        finish.call
        current = { phone: match[1] }
      elsif current && line.include?('Skipping contact')
        current[:error] = 'skipped'
      elsif current && (line.include?('Failed to send WhatsApp template message') || line.include?('"error":'))
        current[:error] = 'send failed'
      elsif line.include?("Campaign #{campaign.id} processing completed")
        finish.call
      end
    end
    finish.call

    puts "Campaign #{campaign.id}: #{sent.size} sent, #{failed.size} failed"
    campaign.update_columns(sent_contacts: sent, failed_contacts: failed) unless ENV['DRY_RUN']
  end
end
