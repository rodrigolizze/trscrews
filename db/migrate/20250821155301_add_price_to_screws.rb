class AddPriceToScrews < ActiveRecord::Migration[7.1]
  def change
    add_column :screws, :price, :decimal, precision: 10, scale: 2
  end
end
