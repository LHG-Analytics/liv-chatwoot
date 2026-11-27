# Rebuilds sent_contacts / failed_contacts for a WhatsApp campaign that ran before send
# tracking existed, by replaying the Whatsapp::OneoffCampaignService log lines.
# Only lines written by the campaign job count; webhook payloads in the same log are ignored.
# delivery_failures maps phone numbers Meta later reported as undeliverable to an error.
class Whatsapp::CampaignStatsBackfillService
  attr_reader :campaign, :log_path, :delivery_failures

  def initialize(campaign:, log_path:, delivery_failures: {})
    @campaign = campaign
    @log_path = log_path
    @delivery_failures = delivery_failures
  end

  def perform
    sent = []
    failed = []
    parse_log.each do |phone, error|
      entry = contact_entry(phone)
      error ||= delivery_failures[phone]
      error ? failed << entry.merge(error: error) : sent << entry
    end

    # A completed campaign rejects regular updates (prevent_completed_campaign_from_update)
    campaign.update_columns(sent_contacts: sent, failed_contacts: failed) # rubocop:disable Rails/SkipsModelValidations
    { sent: sent.size, failed: failed.size }
  end

  def self.read_delivery_failures(path)
    File.foreach(path).each_with_object({}) do |line, failures|
      phone, error = line.strip.split(',', 2)
      failures[phone] = error.presence || 'delivery failed' if phone&.start_with?('+')
    end
  end

  private

  def parse_log
    results = {}
    current = nil
    File.foreach(log_path) do |line|
      if (match = line.match(/Processing contact: .* \((\+\d+)\)/))
        current = match[1]
        results[current] ||= nil
      elsif current && line.include?('Skipping contact')
        results[current] = 'skipped'
      elsif (match = line.match(/Failed to send WhatsApp template message to (\+\d+)/))
        results[match[1]] = 'send failed'
      end
    end
    results
  end

  def contact_entry(phone)
    contact = contacts_by_phone[phone]
    { id: contact&.id, name: contact&.name, phone: phone }
  end

  def contacts_by_phone
    @contacts_by_phone ||= campaign.account.contacts.where.not(phone_number: nil).index_by(&:phone_number)
  end
end
