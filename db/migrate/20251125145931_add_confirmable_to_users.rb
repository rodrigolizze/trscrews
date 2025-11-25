class AddConfirmableToUsers < ActiveRecord::Migration[7.1]
  def up
    # // 1) Add Devise confirmable columns
    add_column :users, :confirmation_token,   :string
    add_column :users, :confirmed_at,        :datetime
    add_column :users, :confirmation_sent_at,:datetime
    add_column :users, :unconfirmed_email,   :string  # // only used if reconfirmable = true

    # // 2) Index for quick lookup by token
    add_index :users, :confirmation_token, unique: true

    # // 3) Mark existing users as confirmed so nobody gets locked out
    User.reset_column_information             # // make sure new columns are visible
    User.update_all(confirmed_at: Time.current)  # // all existing users = "already confirmed"
  end

  def down
    # // Rollback: remove everything we added
    remove_index  :users, :confirmation_token
    remove_column :users, :unconfirmed_email
    remove_column :users, :confirmation_sent_at
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_token
  end
end
