class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.string  :customer_name,  null: false
      t.string  :customer_email, null: false
      t.integer :status, null: false, default: 0 # // enum: 0=draft, 1=placed, 2=cancelled
      t.decimal :subtotal, precision: 10, scale: 2, null: false, default: 0
      t.decimal :shipping, precision: 10, scale: 2, null: false, default: 0
      t.decimal :total,    precision: 10, scale: 2, null: false, default: 0
      t.datetime :placed_at

      t.timestamps
    end
  end
end
