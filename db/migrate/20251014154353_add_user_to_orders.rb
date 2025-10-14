class AddUserToOrders < ActiveRecord::Migration[7.1]
  def change
    # add_reference creates the column + index by default (index: true)
    add_reference :orders, :user, null: true, foreign_key: true
  end
end
