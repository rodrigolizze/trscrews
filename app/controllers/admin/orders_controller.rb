class Admin::OrdersController < Admin::BaseController
  # // we inherit the basic-auth from Admin::BaseController
  # // (remove the test line that raised "ADMIN FILTER TEST")

  def index
    @status = params[:status].presence
    scope = Order.order(placed_at: :desc, created_at: :desc).includes(:order_items)
    scope = scope.where(status: Order.statuses[@status]) if @status
    @orders = scope.limit(200)
  end

  def show
    @order = Order.includes(order_items: [screw: { images_attachments: :blob }]).find(params[:id])
  end

  def update
    @order = Order.find(params[:id])
    desired = params.require(:order).permit(:status)[:status]
    unless %w[placed cancelled shipped].include?(desired)
      redirect_to admin_order_path(@order), alert: "Status inválido." and return
    end
    @order.update!(status: desired)
    redirect_to admin_order_path(@order), notice: "Status atualizado para #{desired}."
  end
end
