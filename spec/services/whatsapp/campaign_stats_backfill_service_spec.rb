require 'rails_helper'

describe Whatsapp::CampaignStatsBackfillService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:campaign) { create(:campaign, inbox: whatsapp_channel.inbox, account: account, campaign_status: :completed) }
  let!(:delivered_contact) { create(:contact, account: account, name: 'Ana', phone_number: '+593911111111') }
  let!(:undelivered_contact) { create(:contact, account: account, name: 'Luis', phone_number: '+593922222222') }
  let!(:skipped_contact) { create(:contact, account: account, name: 'Eva', phone_number: '+593933333333') }
  let(:log_file) do
    file = Tempfile.new('campaign.log')
    file.write(<<~LOG)
      Processing 3 contacts for campaign #{campaign.id}
      Processing contact: Ana (+593911111111)
      Processing contact: Luis (+593922222222)
      {"entry":[{"changes":[{"value":{"statuses":[{"status":"failed","errors":[{"code":131026}]}]}}]}],"error":"x"}
      Processing contact: Eva (+593933333333)
      Skipping contact Eva - liquid variables resolved to blank values
      Campaign #{campaign.id} processing completed
    LOG
    file.close
    file
  end

  it 'rebuilds sent and failed contacts from the log and delivery failures' do
    counts = described_class.new(campaign: campaign, log_path: log_file.path,
                                 delivery_failures: { '+593922222222' => 'meta 131026' }).perform

    campaign.reload
    expect(counts).to eq(sent: 1, failed: 2)
    expect(campaign.sent_contacts.pluck('id')).to eq([delivered_contact.id])
    expect(campaign.failed_contacts.to_h { |entry| [entry['id'], entry['error']] }).to eq(
      undelivered_contact.id => 'meta 131026',
      skipped_contact.id => 'skipped'
    )
  end

  it 'reads delivery failures from a phone,error CSV' do
    csv = Tempfile.new('failures.csv')
    csv.write("+593922222222,meta 131026\n+593944444444\n")
    csv.close

    expect(described_class.read_delivery_failures(csv.path)).to eq(
      '+593922222222' => 'meta 131026',
      '+593944444444' => 'delivery failed'
    )
  end
end
