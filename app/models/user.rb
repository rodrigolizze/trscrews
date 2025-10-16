class User < ApplicationRecord
  has_many :orders, dependent: :nullify
  has_many :shipping_addresses, dependent: :destroy
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Optional helper: quick way to get the default (or first) address
  def default_shipping_address
    shipping_addresses.find_by(is_default: true) || shipping_addresses.first
  end
end
