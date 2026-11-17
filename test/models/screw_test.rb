require "test_helper"

class ScrewTest < ActiveSupport::TestCase
  def screw(**attrs)
    Screw.new({ description: "Parafuso", price: 10, stock: 1 }.merge(attrs))
  end

  test "reads diameter and pitch from the thread in its usual spellings" do
    assert_equal [12.0, 1.5],  screw(thread: "M12x1,5").then { |s| [s.thread_diameter, s.thread_pitch] }
    assert_equal [8.0, 1.25],  screw(thread: "M8-1,25").then { |s| [s.thread_diameter, s.thread_pitch] }
    assert_equal [14.0, 1.5],  screw(thread: "M14 x 1.5").then { |s| [s.thread_diameter, s.thread_pitch] }
  end

  test "falls back to the coarse ISO pitch when the thread has none" do
    assert_equal 1.5, screw(thread: "M10").thread_pitch
  end

  test "a wheel bolt gets a hex head with a conical seat" do
    spec = screw(description: "Parafuso de roda", thread: "M12x1,5", thread_length: 26).viewer_spec
    assert_equal %w[hex conical], spec.values_at(:head, :seat)
    assert_equal 26.0, spec[:length]
    assert_equal 17, spec[:wrench]
  end

  test "a spherical seat is recognised in the description" do
    assert_equal "spherical", screw(description: "Parafuso de roda assento esférico").viewer_spec[:seat]
  end

  test "guesses the head of a brake disc torx, an oil drain plug and a wheel lock" do
    assert_equal "torx_countersunk", screw(description: "Parafuso Torx do Disco de Freio").viewer_spec[:head]
    assert_equal "drain_plug",       screw(description: "Bujão do cárter").viewer_spec[:head]
    lock = screw(description: "Parafuso antifurto para roda").viewer_spec
    assert_equal %w[lock conical], lock.values_at(:head, :seat)
  end

  test "maps the surface treatment to a material finish" do
    assert_equal "zinc",      screw(surface_treatment: "Zincado").viewer_spec[:finish]
    assert_equal "phosphate", screw(surface_treatment: "Fosfatizado").viewer_spec[:finish]
    assert_equal "geomet",    screw(surface_treatment: "Geomet").viewer_spec[:finish]
    assert_equal "steel",     screw(surface_treatment: nil).viewer_spec[:finish]
  end

  test "uses sensible defaults when the thread and length are missing" do
    spec = screw(thread: nil, thread_length: nil).viewer_spec
    assert_equal 12.0, spec[:diameter]
    assert_equal 30.0, spec[:length]
  end

  test "stamps the resistance class under the TR mark" do
    assert_equal "10.9", screw(resistance_class: "10.9").viewer_spec[:marking]
    assert_nil screw(resistance_class: "").viewer_spec[:marking]
  end

  test "recognises phillips pan heads and flanged hex heads" do
    assert_equal "phillips_pan", screw(description: "Parafuso Philips cabeça panela").viewer_spec[:head]
    flange = screw(description: "Parafuso sextavado flangeado").viewer_spec
    assert_equal %w[hex_flange flat], flange.values_at(:head, :seat)
  end
end
