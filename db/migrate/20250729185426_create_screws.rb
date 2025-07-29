class CreateScrews < ActiveRecord::Migration[7.1]
  def change
    create_table :screws do |t|
      t.string :name
      t.text :description
      t.decimal :price

      t.timestamps
    end
  end
end
