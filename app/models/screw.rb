# app/models/screw.rb
class Screw < ApplicationRecord
  # == Media ==
  has_many_attached :images

  # == FriendlyId (pretty URLs) ==
  # // 1) Enable the FriendlyId API on this model
  extend FriendlyId

  # // 2) Tell FriendlyId which fields compose the slug.
  # //    We provide a list of "candidates"; if one is taken, it tries the next.
  # //    Example slugs it will try in order:
  # //    - "parafuso-hex-m6x20"
  # //    - "parafuso-hex-m6x20-vw"
  # //    - "parafuso-hex-m6x20-vw-golf"
  friendly_id :slug_candidates, use: :slugged

  # // 3) When should we regenerate the slug?
  # //    If slug is blank (new record) OR the important parts changed.
  def should_generate_new_friendly_id?
    slug.blank? ||
      will_save_change_to_description? ||
      will_save_change_to_thread? ||
      will_save_change_to_automaker? ||
      will_save_change_to_model?
  end

  # // 4) Provide the list of candidates (ordered by preference)
  def slug_candidates
    # // Normalize nil to "" to avoid "nil" in URLs
    desc  = description.to_s
    rosca = thread.to_s
    maker = automaker.to_s
    model = self.model.to_s
    [
      [desc, rosca],                # "parafuso-hex-m6x20"
      [desc, rosca, maker],         # "parafuso-hex-m6x20-vw"
      [desc, rosca, maker, model]   # "parafuso-hex-m6x20-vw-golf"
    ]
  end

  # == Validations ==
  validates :price, numericality: { greater_than_or_equal_to: 0 }, presence: true
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slug, uniqueness: true, allow_nil: true

  # == Entry point used by the controller -----------------------------------
  # // Apply simple filters based on params
  def self.apply_filters(filter_params = {})
    all
      .by_automaker(filter_params[:automaker])
      .by_model(filter_params[:model])
      .by_thread(filter_params[:thread])
      .by_surface(filter_params[:surface_treatment])
  end

  # == Convenience helpers (used by views) ==
  def in_stock?
    stock.to_i > 0
  end

  def out_of_stock?
    !in_stock?
  end

  # == Safe LIKE helper (class method) ==
  # // Normalize and make a safe SQL pattern from user input
  def self.safe_pattern(str)
    return nil if str.blank?
    "%#{sanitize_sql_like(str.to_s.downcase.strip)}%"
  end

  # == Flexible filtering scopes (case-insensitive, partial matches) ==
  scope :by_automaker, ->(make) do
    if (pat = safe_pattern(make))
      where("LOWER(COALESCE(automaker, '')) LIKE ?", pat)
    else
      all
    end
  end

  scope :by_model, ->(model) do
    if (pat = safe_pattern(model))
      where("LOWER(COALESCE(model, '')) LIKE ?", pat)
    else
      all
    end
  end

  scope :by_thread, ->(t) do
    if (pat = safe_pattern(t))
      where("LOWER(COALESCE(thread, '')) LIKE ?", pat)
    else
      all
    end
  end

  scope :by_surface, ->(s) do
    if (pat = safe_pattern(s))
      where("LOWER(COALESCE(surface_treatment, '')) LIKE ?", pat)
    else
      all
    end
  end

  # == Broad search across multiple columns (SQLite & Postgres friendly) ==
  scope :search, ->(q) do
    if (pat = safe_pattern(q))
      where(
        "LOWER(COALESCE(description, ''))        LIKE :q OR
         LOWER(COALESCE(thread, ''))             LIKE :q OR
         LOWER(COALESCE(automaker, ''))          LIKE :q OR
         LOWER(COALESCE(model, ''))              LIKE :q OR
         LOWER(COALESCE(surface_treatment, ''))  LIKE :q",
        q: pat
      )
    else
      all
    end
  end

  # == Simple stock scope ==
  scope :in_stock, -> { where("stock > 0") }
end
