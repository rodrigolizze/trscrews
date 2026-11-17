# Optional shape fields for the product 3D viewer (stage 2). Blank means
# "guess from the description" (Screw#viewer_spec), so existing products keep
# working without being edited. Nullable columns, no backfill: safe to run live.
class AddShapeFieldsToScrews < ActiveRecord::Migration[8.1]
  def change
    add_column :screws, :head_type, :string
    add_column :screws, :seat_type, :string
    add_column :screws, :wrench_size, :integer
  end
end
