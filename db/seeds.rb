# db/seeds.rb
#
# Synthetic catalog data for local development. Product names are in pt-BR because
# they are user-facing; everything else follows the backend-in-English convention.
#
# The dataset is sized and shaped to exercise:
#   - the four /screws filters (automaker, model, thread, surface_treatment)
#   - pagination (22 records against pagy's effective limit of 20 → 2 pages)
#   - friendly_id slugs (every description is distinct → every slug is distinct)
#   - the out-of-stock card/badge path (one record with stock: 0)
#
# Safe to re-run: records are matched by description, and images are only attached
# when the record has none yet.

abort("db/seeds.rb is development/test only — refusing to run in production.") if Rails.env.production?

# Attaching images is opt-out because variants need libvips (or ImageMagick) on the
# host; without it the pages still render, but the thumbnails 500 on request.
attach_images = ENV.fetch("SEED_IMAGES", "1") == "1"

SCREWS = [
  { description: "Parafuso de Roda Sextavado Fiat Argo M12-1,25x22",          thread: "M12-1,25", thread_length: 22.0, resistance_class: "10.9",  surface_treatment: "Geomet",       automaker: "Fiat",       model: "Argo",     price: 19.90, stock: 40 },
  { description: "Parafuso de Roda Sextavado Fiat Fastback M12-1,25x26",      thread: "M12-1,25", thread_length: 26.0, resistance_class: "10.9",  surface_treatment: "Zincado",      automaker: "Fiat",       model: "Fastback", price: 21.50, stock: 25 },
  { description: "Parafuso de Roda Sextavado Volkswagen Golf M14-1,5x25",     thread: "M14-1,5",  thread_length: 25.0, resistance_class: "10.9",  surface_treatment: "Zincado",      automaker: "Volkswagen", model: "Golf",     price: 24.50, stock: 30 },
  { description: "Parafuso de Roda Sextavado Volkswagen T-Cross M14-1,5x28",  thread: "M14-1,5",  thread_length: 28.0, resistance_class: "10.9",  surface_treatment: "Geomet",       automaker: "Volkswagen", model: "T-Cross",  price: 26.90, stock: 18 },
  { description: "Parafuso de Roda Sextavado Chevrolet Onix M12-1,5x28",      thread: "M12-1,5",  thread_length: 28.0, resistance_class: "8.8",   surface_treatment: "Geomet",       automaker: "Chevrolet",  model: "Onix",     price: 21.00, stock: 60 },
  { description: "Parafuso de Roda Sextavado Chevrolet Tracker M12-1,5x30",   thread: "M12-1,5",  thread_length: 30.0, resistance_class: "8.8",   surface_treatment: "Oxidado",      automaker: "Chevrolet",  model: "Tracker",  price: 22.40, stock: 12 },
  { description: "Parafuso de Roda Sextavado Ford Ka M12-1,5x27",             thread: "M12-1,5",  thread_length: 27.0, resistance_class: "10.9",  surface_treatment: "Zincado",      automaker: "Ford",       model: "Ka",       price: 20.30, stock: 22 },
  { description: "Parafuso de Roda Sextavado Ford Ranger M14-1,5x32",         thread: "M14-1,5",  thread_length: 32.0, resistance_class: "10.9",  surface_treatment: "Fosfatizado",  automaker: "Ford",       model: "Ranger",   price: 29.90, stock: 9 },
  { description: "Parafuso de Roda Sextavado Renault Duster M14-1,5x27",      thread: "M14-1,5",  thread_length: 27.0, resistance_class: "8.8",   surface_treatment: "Oxidado",      automaker: "Renault",    model: "Duster",   price: 18.40, stock: 35 },
  { description: "Parafuso de Roda Sextavado Renault Kwid M12-1,25x24",       thread: "M12-1,25", thread_length: 24.0, resistance_class: "8.8",   surface_treatment: "Zincado",      automaker: "Renault",    model: "Kwid",     price: 17.60, stock: 50 },
  { description: "Parafuso de Roda Sextavado Honda Civic M12-1,5x22",         thread: "M12-1,5",  thread_length: 22.0, resistance_class: "10.9",  surface_treatment: "Geomet",       automaker: "Honda",      model: "Civic",    price: 20.90, stock: 28 },
  { description: "Parafuso de Roda Sextavado Honda HR-V M12-1,5x26",          thread: "M12-1,5",  thread_length: 26.0, resistance_class: "10.9",  surface_treatment: "Zincado",      automaker: "Honda",      model: "HR-V",     price: 22.10, stock: 0 },
  { description: "Parafuso de Roda Sextavado Toyota Corolla M14-1,5x28",      thread: "M14-1,5",  thread_length: 28.0, resistance_class: "10.9",  surface_treatment: "Geomet",       automaker: "Toyota",     model: "Corolla",  price: 23.30, stock: 45 },
  { description: "Parafuso de Roda Sextavado Hyundai HB20 M12-1,5x25",        thread: "M12-1,5",  thread_length: 25.0, resistance_class: "8.8",   surface_treatment: "Zincado",      automaker: "Hyundai",    model: "HB20",     price: 19.20, stock: 33 },
  { description: "Parafuso Allen Cabeça Cilíndrica Inox Toyota Hilux M8-1,25x30", thread: "M8-1,25", thread_length: 30.0, resistance_class: "A2-70", surface_treatment: "Inox polido", automaker: "Toyota",    model: "Hilux",    price: 12.80, stock: 80 },
  { description: "Parafuso Allen Cabeça Cilíndrica Inox Honda Fit M6-1,0x20", thread: "M6-1,0",   thread_length: 20.0, resistance_class: "A2-70", surface_treatment: "Inox polido",  automaker: "Honda",      model: "Fit",      price: 8.90,  stock: 120 },
  { description: "Parafuso Philips Cabeça Panela Volkswagen Polo M6-1,0x16",  thread: "M6-1,0",   thread_length: 16.0, resistance_class: "8.8",   surface_treatment: "Zincado",      automaker: "Volkswagen", model: "Polo",     price: 4.70,  stock: 200 },
  { description: "Parafuso Philips Cabeça Panela Fiat Mobi M6-1,0x25",        thread: "M6-1,0",   thread_length: 25.0, resistance_class: "8.8",   surface_treatment: "Zincado",      automaker: "Fiat",       model: "Mobi",     price: 5.20,  stock: 150 },
  { description: "Parafuso Sextavado Flangeado Chevrolet S10 M10-1,25x35",    thread: "M10-1,25", thread_length: 35.0, resistance_class: "10.9",  surface_treatment: "Fosfatizado",  automaker: "Chevrolet",  model: "S10",      price: 14.60, stock: 65 },
  { description: "Parafuso Sextavado Flangeado Ford Ranger M10-1,25x40",      thread: "M10-1,25", thread_length: 40.0, resistance_class: "10.9",  surface_treatment: "Geomet",       automaker: "Ford",       model: "Ranger",   price: 15.90, stock: 40 },
  { description: "Parafuso Torx do Disco de Freio Renault Sandero M8-1,25x22", thread: "M8-1,25", thread_length: 22.0, resistance_class: "12.9",  surface_treatment: "Oxidado",      automaker: "Renault",    model: "Sandero",  price: 9.40,  stock: 90 },
  { description: "Parafuso Torx do Disco de Freio Hyundai Creta M8-1,25x18",  thread: "M8-1,25",  thread_length: 18.0, resistance_class: "12.9",  surface_treatment: "Fosfatizado",  automaker: "Hyundai",    model: "Creta",    price: 9.10,  stock: 75 }
].freeze

# The repo ships 8 sets of 3 product photos; they cycle across the 22 records.
IMAGE_SETS = (1..8).map { |set| (1..3).map { |n| "screw#{set}_#{n}.jpeg" } }.freeze

puts "🌱 Seeding #{SCREWS.size} screws (images: #{attach_images ? 'on' : 'off'})..."

created = 0
updated = 0
attached = 0

SCREWS.each_with_index do |attributes, index|
  screw = Screw.find_or_initialize_by(description: attributes[:description])
  screw.new_record? ? created += 1 : updated += 1
  screw.assign_attributes(attributes)
  screw.save!

  next unless attach_images
  next if screw.images.attached?

  IMAGE_SETS[index % IMAGE_SETS.size].each do |filename|
    screw.images.attach(
      io: File.open(Rails.root.join("app/assets/images", filename)),
      filename: filename,
      content_type: "image/jpeg"
    )
  end
  attached += 1
end

puts "✅ #{created} created, #{updated} updated, #{attached} with images attached."
puts "   Screw.count = #{Screw.count} · distinct slugs = #{Screw.distinct.count(:slug)}"
