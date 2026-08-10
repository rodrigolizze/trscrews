# frozen_string_literal: true

# NOTE: the year in this migration's filename is a typo.
# The timestamp reads 2025-03-11, but this migration was actually written on
# 2026-03-11 (commit 8f1710e) — the `orders` table itself did not exist in
# March 2025. The wrong year misled an earlier audit into concluding that
# webhooks had been broken for "14+ months"; the real outage window is
# ~2.5 months (2026-03-11, when the controller started depending on this
# table, to 2026-05-25, when the migration finally ran in production).
#
# The filename is deliberately NOT renamed: the version 20250311120000 is
# already recorded in schema_migrations in production, so renaming it would
# make Rails try to re-run this migration and require a manual UPDATE on
# schema_migrations across every environment — real risk for zero benefit.
# See STRIPE_AUDIT.md §4.5 for the full timeline.

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
