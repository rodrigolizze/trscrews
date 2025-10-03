class AddSlugToScrews < ActiveRecord::Migration[7.1]
  def change
    # // 1) add the column (nullable for now so old rows are fine)
    add_column :screws, :slug, :string

    # // 2) unique index so two products can’t share the same slug
    add_index  :screws, :slug, unique: true
  end
end
