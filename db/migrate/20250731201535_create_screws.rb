class CreateScrews < ActiveRecord::Migration[7.1]
  def change
    create_table :screws do |t|
      t.string :description
      t.string :thread
      t.decimal :thread_length
      t.string :resistance_class
      t.string :surface_treatment
      t.string :automaker
      t.string :model

      t.timestamps
    end
  end
end
