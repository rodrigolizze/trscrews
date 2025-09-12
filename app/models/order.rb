class Order < ApplicationRecord
  has_many :order_items, dependent: :destroy

  enum status: { draft: 0, placed: 1, cancelled: 2, shipped: 3 }

  # // Basic presence
  validates :customer_name,  presence: true
  validates :customer_email, presence: true

  # Generate a unique, readable number once the record exists
  after_create_commit :assign_order_number!

  # // Recalculate totals based on order_items
  def recalc_totals!
    self.subtotal = order_items.sum(:line_total)
    # // Shipping: placeholder (flat 0 for now). Change as needed.
    self.shipping = 0
    self.total    = subtotal + shipping
  end

  # // Convenience for adding an item snapshot
  def add_item!(screw, qty)
    qty = qty.to_i
    qty = 1 if qty <= 0

    unit_price = screw.price.to_d
    line_total = unit_price * qty

    order_items.build(screw: screw, quantity: qty, unit_price: unit_price, line_total: line_total)
  end

  private

  def assign_order_number!
    # Format: SC-YYMM-000123 (uses ID, so it's short & unique)
    yy_mm   = created_at.strftime("%y%m")
    number  = format("SC-%s-%06d", yy_mm, id)
    # Avoid extra callbacks by update_column
    update_column(:order_number, number)
  end
end
