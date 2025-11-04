class AddOneDefaultAddressPerUser < ActiveRecord::Migration[7.1]
  def change
    # // Partial unique index: only rows with is_default = TRUE count
    add_index :shipping_addresses, :user_id,
      unique: true,
      where: "is_default = TRUE",
      name: "index_shipping_addresses_one_default_per_user"
  end
end
