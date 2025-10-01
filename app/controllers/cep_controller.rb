# // Minimal controller to query ViaCEP and return normalized JSON
# // Usage: GET /cep/:cep   → { street, district, city, state, cep }
# // Examples: /cep/01311000 or /cep/01311-000
class CepController < ApplicationController
  require "net/http"  # // built-in HTTP client
  require "uri"
  require "json"

  # // GET /cep/:cep
  def lookup
    # // 1) Sanitize input: keep only digits
    cep = params[:cep].to_s.gsub(/\D/, "")

    # // 2) Validate length (ViaCEP expects exactly 8 digits)
    if cep.length != 8
      render json: { error: "CEP inválido" }, status: :unprocessable_entity and return
    end

    # // 3) Build ViaCEP URL
    url = URI.parse("https://viacep.com.br/ws/#{cep}/json/")

    # // 4) Call ViaCEP with small timeouts (so our checkout never hangs)
    begin
      response = Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
        http.request(Net::HTTP::Get.new(url.request_uri))
      end
    rescue StandardError => e
      Rails.logger.error("[ViaCEP] Network error: #{e.class} - #{e.message}")
      render json: { error: "Serviço de CEP indisponível" }, status: :service_unavailable and return
    end

    # // 5) Handle non-200 responses gracefully
    unless response.code.to_i == 200
      Rails.logger.warn("[ViaCEP] HTTP #{response.code} for CEP #{cep}")
      render json: { error: "Falha ao consultar CEP" }, status: :bad_gateway and return
    end

    # // 6) Parse JSON (ViaCEP returns { erro: true } for unknown CEP)
    data = JSON.parse(response.body) rescue {}
    if data["erro"]
      render json: { error: "CEP não encontrado" }, status: :not_found and return
    end

    # // 7) Normalize keys for our form fields
    render json: {
      cep:      data["cep"],         # "01311-000"
      street:   data["logradouro"],  # Rua
      district: data["bairro"],      # Bairro
      city:     data["localidade"],  # Cidade
      state:    data["uf"]           # "SP"
    }
  end
end
