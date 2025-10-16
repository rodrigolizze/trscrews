class Order < ApplicationRecord
  has_many :order_items, dependent: :destroy
  belongs_to :user, optional: true

  enum status: { draft: 0, placed: 1, cancelled: 2, shipped: 3 }

  # // 0=pending, 1=paid, 2=failed
  enum payment_status: { pending: 0, paid: 1, failed: 2 }, _default: :pending

  before_validation :normalize_state

  # // Basic presence
  validates :customer_name,  presence: true
  validates :customer_email, presence: true

  # // Address presence (complement optional on the form; it can stay empty)
  validates :cep, :street, :number, :district, :city, :state, presence: true
  validates :state, length: { is: 2 }

  # // CEP format: accepts "12345-678" or "12345678"
  validates :cep, format: { with: /\A\d{5}-?\d{3}\z/, message: "formato inválido (ex.: 12345-678)" }

  validates :state, inclusion: {
    in: Rails.configuration.x.shipping.uf_codes,                     # // central list
    message: "inválido (use uma UF válida, ex.: SP)"
  }

  # Generate a unique, readable number once the record exists
  after_create_commit :assign_order_number!

  # // Recalculate totals based on order_items
  def recalc_totals!
    self.subtotal = order_items.sum(:line_total)
    # self.shipping = compute_shipping(subtotal)  # // central place to compute shipping
    self.total    = subtotal + (shipping_fee || 0)
  end

  # // Simple shipping rule: R$ 20,00; grátis acima de R$ 150,00
  def compute_shipping(subtotal_value)
    subtotal_value.to_d >= 150 ? 0.to_d : 20.to_d
  end


  # // Convenience for adding an item snapshot
  def add_item!(screw, qty)
    qty = qty.to_i
    qty = 1 if qty <= 0

    unit_price = screw.price.to_d
    line_total = unit_price * qty

    order_items.build(screw: screw, quantity: qty, unit_price: unit_price, line_total: line_total)
  end

  def paid?
    if respond_to?(:payment_status) && self.payment_status.present?
      # If using an enum like payment_status: { pending: 0, paid: 1, cancelled: 2 }
      self.payment_status.to_s == "paid" || self.payment_status == "paid"
    else
      self.paid_at.present?
    end
  end

  # HELPER
  def mark_paid!(method:, reference:)
    update!(payment_status: :paid, paid_at: Time.current,
            payment_method: method, payment_reference: reference)
  end

  def payment_pending?
    if respond_to?(:payment_status) && self.payment_status.present?
      self.payment_status.to_s == "pending"
    else
      !paid?
    end
  end

  private

  def assign_order_number!
    # Format: SC-YYMM-000123 (uses ID, so it's short & unique)
    yy_mm   = created_at.strftime("%y%m")
    number  = format("SC-%s-%06d", yy_mm, id)
    # Avoid extra callbacks by update_column
    update_column(:order_number, number)
  end

  def normalize_state
    self.state = state.to_s.strip.upcase
  end
end
