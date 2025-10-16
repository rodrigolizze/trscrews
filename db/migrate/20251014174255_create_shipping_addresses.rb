class CreateShippingAddresses < ActiveRecord::Migration[7.1]
  def change
    create_table :shipping_addresses do |t|
      # // Who owns this address
      t.references :user, null: false, foreign_key: true, index: true

      # // Basic fields (mirrors what we already collect on Order)
      t.string :recipient_name, null: false      # // Nome de quem recebe
      t.string :cep,            null: false      # // CEP (format livre, validamos depois)
      t.string :street,         null: false      # // Rua/Logradouro
      t.string :number,         null: false      # // Número
      t.string :complement                           # // Complemento (opcional)
      t.string :district,       null: false      # // Bairro
      t.string :city,           null: false      # // Cidade
      t.string :state,          null: false      # // UF (ex.: "SP")

      # // Mark one as default per user (we'll enforce app-side)
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    # // Helpful composite index to quickly find the default address of a user
    add_index :shipping_addresses, [:user_id, :is_default]
  end
end
