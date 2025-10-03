# lib/tasks/backfill_slugs.rake
# // Usage:
# //   bin/rails screws:backfill_slugs          # real run
# //   bin/rails screws:backfill_slugs[true]    # dry-run (prints what it would do)
#
# // This task iterates over all Screws and (re)generates a slug when it's blank.
# // It uses FriendlyId's should_generate_new_friendly_id? logic.
namespace :screws do
  desc "Backfill FriendlyId slugs for Screws (pass [true] for dry-run)"
  task :backfill_slugs, [:dry_run] => :environment do |_t, args|
    dry_run = ActiveModel::Type::Boolean.new.cast(args[:dry_run])

    puts "== Screws slug backfill #{dry_run ? '(dry-run)' : ''} =="
    total   = Screw.count
    updated = 0
    skipped = 0
    errors  = 0

    Screw.find_each(batch_size: 500) do |s|
      if s.slug.present?
        skipped += 1
        next
      end

      # // Force regeneration if needed (slug blank triggers it)
      s.slug = nil

      if dry_run
        puts "[DRY] would set slug for id=#{s.id} (candidates: #{s.slug_candidates.map { |arr| Array(arr).join('-') }.join(' | ')})"
        next
      end

      if s.save
        updated += 1
        puts "OK  id=#{s.id} → slug=#{s.slug}"
      else
        errors += 1
        puts "ERR id=#{s.id} → #{s.errors.full_messages.to_sentence}"
      end
    end

    puts "== Done: total=#{total} updated=#{updated} skipped=#{skipped} errors=#{errors} =="
    exit(1) if errors.positive? && !dry_run
  end
end
