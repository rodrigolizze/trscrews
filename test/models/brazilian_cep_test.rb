require "test_helper"

class BrazilianCepTest < ActiveSupport::TestCase
  test "maps capital CEPs to their states" do
    {
      "02055-050" => "SP", "20040-020" => "RJ", "30130-010" => "MG",
      "80010-000" => "PR", "90010-150" => "RS", "70040-010" => "DF",
      "40026-032" => "BA", "69005-010" => "AM", "66010-000" => "PA",
      "69301-000" => "RR", "78005-000" => "MT", "79002-000" => "MS"
    }.each do |cep, uf|
      assert_equal uf, BrazilianCep.uf_for(cep), "CEP #{cep} deveria ser #{uf}"
    end
  end

  test "handles states split across two CEP ranges" do
    assert_equal "AM", BrazilianCep.uf_for("69400-000")
    assert_equal "DF", BrazilianCep.uf_for("73000-000")
    assert_equal "GO", BrazilianCep.uf_for("72800-000")
    assert_equal "RO", BrazilianCep.uf_for("76801-000")
    assert_equal "RO", BrazilianCep.uf_for("78900-000")
  end

  test "accepts CEP with or without the dash" do
    assert_equal "SP", BrazilianCep.uf_for("02055050")
  end

  test "returns nil for malformed or unassigned CEPs" do
    assert_nil BrazilianCep.uf_for("123")
    assert_nil BrazilianCep.uf_for("")
    assert_nil BrazilianCep.uf_for(nil)
    assert_nil BrazilianCep.uf_for("00999-999")
  end
end
