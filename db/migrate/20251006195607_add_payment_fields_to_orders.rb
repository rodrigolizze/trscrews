class AddPaymentFieldsToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :payment_status, :integer, null: false, default: 0  # 0=pending
    add_column :orders, :paid_at, :datetime
    add_column :orders, :payment_method, :string
    add_column :orders, :payment_reference, :string
    add_index  :orders, :payment_status
    add_index  :orders, :payment_reference
  end
end
