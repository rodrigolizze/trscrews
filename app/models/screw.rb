# app/models/screw.rb
class Screw < ApplicationRecord
  has_many_attached :images

  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # -- Helpers --------------------------------------------------------------
  # Normalize and make a safe SQL pattern from user input
  def self.safe_pattern(str)
    return nil if str.blank?
    "%#{sanitize_sql_like(str.to_s.downcase.strip)}%"
  end

  # -- Flexible filtering scopes (case-insensitive, partial matches) --------
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

  # -- Broad search across multiple columns (SQLite & Postgres friendly) ----
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

  # -- Entry point used by the controller -----------------------------------
  def self.apply_filters(filter_params = {})
    all
      .by_automaker(filter_params[:automaker])
      .by_model(filter_params[:model])
      .by_thread(filter_params[:thread])
      .by_surface(filter_params[:surface_treatment])
  end

  # // Nice helpers for views/logic
  def in_stock?
    stock.to_i > 0
  end

  def out_of_stock?
    !in_stock?
  end

  # // scope for queries
  scope :in_stock, -> { where("stock > 0") }
end
