class AddShippingAddressToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :cep,        :string,  null: false, default: ""   # // "12345-678"
    add_column :orders, :street,     :string,  null: false, default: ""   # // Rua
    add_column :orders, :number,     :string,  null: false, default: ""   # // Número (string p/ "123A")
    add_column :orders, :complement, :string,  null: false, default: ""   # // apto/bloco - opcional no form
    add_column :orders, :district,   :string,  null: false, default: ""   # // Bairro
    add_column :orders, :city,       :string,  null: false, default: ""   # // Cidade
    add_column :orders, :state,      :string,  null: false, default: ""   # // UF (SP/RJ/…)
  end
end
