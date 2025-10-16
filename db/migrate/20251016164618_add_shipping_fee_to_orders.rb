class AddShippingFeeToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :shipping_fee, :decimal,
      precision: 10, scale: 2, null: false, default: 0
      # // precision/scale: values like 99999999.99 are safe
      # // default 0 keeps old orders valid and avoids nil math
  end
end
