# frozen_string_literal: true

class CreateStripeWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :stripe_webhook_events do |t|
      t.string :stripe_event_id, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :stripe_webhook_events, :stripe_event_id, unique: true
  end
end
