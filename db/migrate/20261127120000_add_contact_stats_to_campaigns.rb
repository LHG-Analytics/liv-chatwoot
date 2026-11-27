class AddContactStatsToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :sent_contacts, :jsonb, default: []
    add_column :campaigns, :failed_contacts, :jsonb, default: []
  end
end
