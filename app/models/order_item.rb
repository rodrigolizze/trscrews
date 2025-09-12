class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :screw

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :line_total, numericality: { greater_than_or_equal_to: 0 }
end
