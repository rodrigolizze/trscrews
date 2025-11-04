class AddUfCheckConstraints < ActiveRecord::Migration[7.1]
  # // UFs válidas (maiúsculas), já devidamente 'quoted' para o SQL IN (...)
  UF_SQL_LIST = %w[
    AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO
  ].map { |uf| "'#{uf}'" }.join(", ").freeze

  def change
    # ------------------------------------------------------------
    # 1) Normaliza dados existentes (UPPER + TRIM)
    # ------------------------------------------------------------
    execute "UPDATE orders              SET state = UPPER(TRIM(state)) WHERE state IS NOT NULL;"
    execute "UPDATE shipping_addresses  SET state = UPPER(TRIM(state)) WHERE state IS NOT NULL;"

    # ------------------------------------------------------------
    # 2) Backfill: qualquer valor nulo OU inválido -> 'SP'
    #    (Evita violar NOT NULL e deixa tudo consistente)
    # ------------------------------------------------------------
    execute "UPDATE orders              SET state = 'SP' WHERE state IS NULL OR state NOT IN (#{UF_SQL_LIST});"
    execute "UPDATE shipping_addresses  SET state = 'SP' WHERE state IS NULL OR state NOT IN (#{UF_SQL_LIST});"

    # ------------------------------------------------------------
    # 3) Adiciona as CHECK CONSTRAINTS (sem permitir nulos)
    # ------------------------------------------------------------
    add_check_constraint :shipping_addresses,
      "state IN (#{UF_SQL_LIST})",
      name: "shipping_addresses_state_valid_uf"

    add_check_constraint :orders,
      "state IN (#{UF_SQL_LIST})",
      name: "orders_state_valid_uf"
  end
end
