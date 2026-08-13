ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# WORKAROUND TEMPORÁRIO — REMOVER ao subir para o Devise 5.0 (Etapa F, isolada;
# ver UPGRADE_PLAN.md). A suíte deve seguir verde sem esta linha depois disso.
#
# Bug: lazy route loading do Rails 8.0 (rails/rails#52353) + Devise 4.9.4
# (heartcombo/devise#5694). O Rails 8.0 desenha as rotas sob demanda em development
# e test, e o Devise 4.9.4 resolve Devise.mappings durante o carregamento das rotas.
# Qualquer chamada a Devise::Mapping.find_scope! antes de uma rota ser visitada
# — sign_in, sign_out, URL helpers de Devise, mailer — falha com
# "Could not find a valid mapping".
#
# Reproduzido neste repo em 2026-08-12: no boot da suíte, routes @loaded == false,
# Devise.mappings == [] e find_scope!(User) levanta RuntimeError. Os 17 testes
# passam hoje apenas porque nenhum chama sign_in; o primeiro que chamar quebra.
#
# execute_unless_loaded (NÃO reload_routes!) desenha as rotas uma única vez, via
# `unless @loaded`, em vez de redesenhar a cada chamada. É a mesma chamada que o
# Devise 5.0 embutiu em find_scope! (heartcombo/devise#5695). `try` porque o método
# só existe a partir do Rails 8.0.
Rails.application.routes_reloader.try(:execute_unless_loaded)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
