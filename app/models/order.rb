class Order < ApplicationRecord
  has_many :order_items, dependent: :destroy
  belongs_to :user, optional: true

  include CepMatchesState

  enum :status, { draft: 0, placed: 1, cancelled: 2, shipped: 3 }

  # // 0=pending, 1=paid, 2=failed
  enum :payment_status, { pending: 0, paid: 1, failed: 2 }, default: :pending

  before_validation :normalize_state

  # Payment window: a placed order reserves its stock for this long. The Stripe
  # Checkout Session expires at the same deadline (expires_at), so nobody can pay
  # after the stock is released. The sweeper task waits an extra grace period in
  # case the checkout.session.expired webhook is late or lost.
  PAYMENT_WINDOW = 8.hours
  EXPIRY_GRACE   = 15.minutes

  scope :expired_unpaid, -> {
    placed.pending.where("placed_at < ?", (PAYMENT_WINDOW + EXPIRY_GRACE).ago)
  }

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
    # // Soma em memória: recalc_totals! roda antes do save, e um SUM() em SQL
    # // sobre associação não persistida devolve 0. Mesmo critério de items_subtotal.
    self.subtotal = order_items.sum { |i| i.line_total.to_d }

    # mantém `shipping` em sincronia com `shipping_fee`
    self.shipping = (shipping_fee || shipping || 0).to_d

    # total = subtotal + frete
    self.total = subtotal.to_d + shipping
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

  # Deadline to pay (and when the Stripe session expires).
  def payment_deadline
    (placed_at || created_at) + PAYMENT_WINDOW
  end

  def payment_expired?
    cancelled? || (payment_pending? && Time.current >= payment_deadline)
  end

  # Cancels an unpaid order and puts its items back in stock. Safe to call more
  # than once and from concurrent callers (webhook + sweeper): the row lock plus
  # the status check make the second call a no-op. Returns true only when THIS
  # call cancelled the order.
  def expire_and_restock!
    cancelled_now = false
    with_lock do
      next unless placed? && payment_pending?

      order_items.includes(:screw).each do |item|
        screw = item.screw
        next unless screw
        screw.with_lock { screw.update!(stock: screw.stock + item.quantity.to_i) }
      end
      update!(status: :cancelled, payment_status: :failed)
      cancelled_now = true
    end
    cancelled_now
  end

  def items_subtotal
    # // Soma garantida dos itens, sem depender do campo subtotal estar salvo
    order_items.sum { |item| item.line_total.to_d }
  end

  def shipping_amount
    # // Usa o campo que existir/preferir
    (shipping_fee || shipping || 0).to_d
  end

  def total_amount
    # // Total sempre consistente = itens + frete
    items_subtotal + shipping_amount
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
