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

  # == Shape (3D viewer) ==
  # Labels shown in the admin. Blank = guess from the description.
  HEAD_TYPES = {
    "hex"              => "Sextavada",
    "hex_flange"       => "Sextavada flangeada",
    "lock"             => "Antifurto (chave codificada)",
    "drain_plug"       => "Bujão de cárter (com arruela)",
    "torx"             => "Torx cilíndrica",
    "torx_countersunk" => "Torx escareada (disco de freio)",
    "allen"            => "Allen cilíndrica",
    "phillips_pan"     => "Philips cabeça panela"
  }.freeze
  SEAT_TYPES = {
    "conical"   => "Cônico 60°",
    "spherical" => "Esférico",
    "flat"      => "Plano"
  }.freeze

  validates :head_type, inclusion: { in: HEAD_TYPES.keys }, allow_blank: true
  validates :seat_type, inclusion: { in: SEAT_TYPES.keys }, allow_blank: true
  validates :wrench_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 60 },
                          allow_nil: true

  # == Validations ==
  validates :price, numericality: { greater_than_or_equal_to: 0 }, presence: true
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slug, uniqueness: true, allow_nil: true

  # == 3D viewer -------------------------------------------------------------
  # Shape of the parametric 3D model on the product page. head_type, seat_type and
  # wrench_size come from the admin when filled; otherwise they are guessed from
  # the description (and the wrench from the diameter).

  # Coarse ISO pitch, used when the thread has no pitch ("M10").
  COARSE_PITCH = { 5 => 0.8, 6 => 1.0, 8 => 1.25, 10 => 1.5, 12 => 1.75, 14 => 2.0, 16 => 2.0 }.freeze
  # Typical wrench size (across flats, mm) by nominal diameter.
  WRENCH_SIZE  = { 5 => 8, 6 => 10, 8 => 13, 10 => 16, 12 => 17, 14 => 19, 16 => 22 }.freeze

  # use_overrides: false gives the pure guess (the admin preview starts from it
  # and applies the select boxes on top while editing).
  def viewer_spec(use_overrides: true)
    diameter = thread_diameter
    head     = (head_type.presence if use_overrides) || guessed_head_type
    {
      diameter: diameter,
      pitch:    thread_pitch(diameter),
      length:   (thread_length.presence || (diameter * 2.5)).to_f.round(2),
      head:     head,
      seat:     (seat_type.presence if use_overrides) || guessed_seat_type(head),
      wrench:   (wrench_size if use_overrides) || WRENCH_SIZE.fetch(diameter.round, (diameter * 1.5).round),
      finish:   finish_key,
      marking:  resistance_class.to_s.strip.presence  # stamped under "TR" on the head
    }
  end

  # "M12x1,5" / "M8-1,25" / "M14 x 1.5" / "M10" -> 12.0 / 8.0 / 14.0 / 10.0 (default 12)
  def thread_diameter
    match = thread.to_s.match(/M\s*(\d+(?:[.,]\d+)?)/i)
    match ? match[1].tr(",", ".").to_f : 12.0
  end

  def thread_pitch(diameter = thread_diameter)
    match = thread.to_s.match(/M\s*\d+(?:[.,]\d+)?\s*[x×*\-]\s*(\d+(?:[.,]\d+)?)/i)
    return match[1].tr(",", ".").to_f if match
    COARSE_PITCH.fetch(diameter.round, 1.5)
  end

  private

  def viewer_text
    [description, model].compact.join(" ").downcase
  end

  def guessed_head_type
    text = viewer_text
    if text.match?(/anti.?furto|trava de roda/)        then "lock"
    elsif text.match?(/c[aá]rter|buj[aã]o|dreno/)      then "drain_plug"
    elsif text.match?(/torx/)
      text.match?(/disco|freio|escareado/) ? "torx_countersunk" : "torx"
    elsif text.match?(/allen/)                          then "allen"
    elsif text.match?(/phill?ips/)                      then "phillips_pan"
    elsif text.match?(/flangead/)                       then "hex_flange"
    else "hex"
    end
  end

  def guessed_seat_type(head)
    text = viewer_text
    return "flat" if %w[drain_plug torx_countersunk torx allen phillips_pan hex_flange].include?(head)
    return "spherical" if text.match?(/esf[eé]ric|abaulad/)
    return "conical"   if head == "lock" || text.match?(/roda|c[oô]nic/)
    "flat"
  end

  def finish_key
    case surface_treatment.to_s.downcase
    when /cromad|chrom/        then "chrome"
    when /geomet|dacromet/     then "geomet"
    when /fosfat/              then "phosphate"
    when /pret|black|oxid/     then "black"
    when /zinc/                then "zinc"
    else "steel"
    end
  end

  public

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
    # // Se não tem busca, devolve a relação sem filtrar
    return all if q.blank?

    # // 1) Quebra a busca em palavras: "Parafuso Toyota" => ["Parafuso", "Toyota"]
    terms = q.to_s.strip.split(/\s+/)

    # // 2) Para cada palavra:
    # //    - ela pode aparecer em QUALQUER campo (OR)
    # //    - todas as palavras precisam bater (AND) porque aplicamos um where por termo
    terms.reduce(all) do |relation, term|
      # // Evita que caracteres especiais do LIKE (% e _) quebrem a busca
      safe_term = ActiveRecord::Base.sanitize_sql_like(term)
      pattern = "%#{safe_term}%"

      relation.where(
        "description ILIKE :p OR thread ILIKE :p OR automaker ILIKE :p OR model ILIKE :p OR surface_treatment ILIKE :p",
        p: pattern
      )
    end
  end

  # == Simple stock scope ==
  scope :in_stock, -> { where("stock > 0") }
end
