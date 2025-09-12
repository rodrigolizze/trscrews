class CreateOrderItems < ActiveRecord::Migration[7.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :screw, null: false, foreign_key: true

      t.integer :quantity,    null: false, default: 1
      t.decimal :unit_price,  precision: 10, scale: 2, null: false, default: 0  # // snapshot of Screw.price
      t.decimal :line_total,  precision: 10, scale: 2, null: false, default: 0  # // quantity * unit_price

      t.timestamps
    end
  end
end
