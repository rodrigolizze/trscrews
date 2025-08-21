puts "🌱 Seeding screws..."

screws = Screw.create!([
  { description: "Parafuso de Roda linha Fiat M12-1,25x22", thread: "M12-1,25", thread_length: 22.0, resistance_class: "10.9", surface_treatment: "Geomet", automaker: "Fiat", model: "Fastback", price: 19.90 },
  { description: "Parafuso para roda Volkswagen M14-1,5x25", thread: "M14-1,5", thread_length: 25.0, resistance_class: "10.9", surface_treatment: "Zincado", automaker: "Volkswagen", model: "Golf", price: 24.50 },
  { description: "Parafuso para roda Chevrolet M12-1,5x28", thread: "M12-1,5", thread_length: 28.0, resistance_class: "8.8", surface_treatment: "Geomet", automaker: "Chevrolet", model: "Onix", price: 21.00 },
  { description: "Parafuso de roda Ford M12-1,5x30", thread: "M12-1,5", thread_length: 30.0, resistance_class: "10.9", surface_treatment: "Zincado", automaker: "Ford", model: "Focus", price: 22.75 },
  { description: "Parafuso de roda Renault M14-1,5x27", thread: "M14-1,5", thread_length: 27.0, resistance_class: "8.8", surface_treatment: "Oxidado", automaker: "Renault", model: "Duster", price: 18.40 },
  { description: "Parafuso para roda Honda M12-1,5x22", thread: "M12-1,5", thread_length: 22.0, resistance_class: "10.9", surface_treatment: "Geomet", automaker: "Honda", model: "Civic", price: 20.90 },
  { description: "Parafuso roda Peugeot M12-1,25x26", thread: "M12-1,25", thread_length: 26.0, resistance_class: "8.8", surface_treatment: "Zincado", automaker: "Peugeot", model: "208", price: 19.50 },
  { description: "Parafuso para roda Toyota M14-1,5x28", thread: "M14-1,5", thread_length: 28.0, resistance_class: "10.9", surface_treatment: "Geomet", automaker: "Toyota", model: "Corolla", price: 23.30 }
])

puts "✅ Screws created successfully!"

puts "🖼️ Attaching images..."

image_sets = [
  ["screw1_1.jpeg", "screw1_2.jpeg", "screw1_3.jpeg"],
  ["screw2_1.jpeg", "screw2_2.jpeg", "screw2_3.jpeg"],
  ["screw3_1.jpeg", "screw3_2.jpeg", "screw3_3.jpeg"],
  ["screw4_1.jpeg", "screw4_2.jpeg", "screw4_3.jpeg"],
  ["screw5_1.jpeg", "screw5_2.jpeg", "screw5_3.jpeg"],
  ["screw6_1.jpeg", "screw6_2.jpeg", "screw6_3.jpeg"],
  ["screw7_1.jpeg", "screw7_2.jpeg", "screw7_3.jpeg"],
  ["screw8_1.jpeg", "screw8_2.jpeg", "screw8_3.jpeg"]
]

screws.each_with_index do |screw, index|
  image_sets[index].each do |filename|
    screw.images.attach(
      io: File.open(Rails.root.join("app/assets/images/#{filename}")),
      filename: filename
    )
  end
end

puts "✅ Images attached!"
