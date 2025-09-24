class AddStockToScrews < ActiveRecord::Migration[7.1]
  def change
    # // Stock is integer, never null; default 0 so existing rows are safe
    add_column :screws, :stock, :integer, null: false, default: 0
    add_index  :screws, :stock
  end
end
