# app/controllers/admin/screws_controller.rb
class Admin::ScrewsController < ApplicationController
  # // Gate: basic auth you already use in admin
  before_action :require_admin_basic_auth

  # // Load one screw for show/edit/update/destroy/image purge
  before_action :set_screw, only: [:show, :edit, :update, :destroy, :destroy_image]

  # == Index ===============================================================
  # // List screws (simple search + order to help finding items)
  def index
    # // 1) get raw params (strings), keep it simple
    @q   = params[:q].to_s.strip
    @sort = params[:sort].presence_in(%w[created_at price stock automaker model]) || "created_at"
    @dir  = params[:dir].presence_in(%w[asc desc]) || "desc"

    # // 2) base scope (includes images to avoid N+1 in views)
    scope = Screw.includes(images_attachments: :blob).all

    # // 3) quick ILIKE search across a few columns (works in Postgres)
    if @q.present?
      scope = scope.where(
        "description ILIKE :q OR automaker ILIKE :q OR model ILIKE :q OR thread ILIKE :q",
        q: "%#{@q}%"
      )
    end

    # // 4) order and limit (raise the limit later or paginate if you want)
    @screws = scope.order(Arel.sql("#{@sort} #{@dir}")).limit(300)
  end

  # == Show ==============================================================
  # // Optional page showing one screw (handy for admins)
  def show
  end

  # == New / Create ======================================================
  def new
    @screw = Screw.new
  end

  def create
    @screw = Screw.new(screw_params.except(:images))
    if @screw.save
      if params[:screw][:images].present?
        @screw.images.attach(params[:screw][:images])
      end
      redirect_to admin_screw_path(@screw), notice: "Produto criado."
    else
      flash.now[:alert] = "Não foi possível criar o produto."
      render :new, status: :unprocessable_entity
    end
  end

  # == Edit / Update =====================================================
  def edit
  end

  def update
    # // 1) Update scalar fields (NOT images)
    if @screw.update(screw_params.except(:images))
      # // 2) Only attach when there are new uploads
      if params[:screw][:images].present?
        @screw.images.attach(params[:screw][:images])
      end
      redirect_to admin_screw_path(@screw), notice: "Produto atualizado."
    else
      flash.now[:alert] = "Não foi possível atualizar o produto."
      render :edit, status: :unprocessable_entity
    end
  end

  # == Destroy ===========================================================
  def destroy
    @screw.destroy
    redirect_to admin_screws_path, notice: "Produto removido."
  end

  # == Destroy one image (Active Storage) ================================
  # DELETE /admin/screws/:id/images/:attachment_id
  def destroy_image
    # // Find the specific attachment by id and purge it
    attachment = @screw.images.attachments.find_by(id: params[:attachment_id])

    if attachment
      attachment.purge
      redirect_to edit_admin_screw_path(@screw), notice: "Imagem removida."
    else
      redirect_to edit_admin_screw_path(@screw), alert: "Imagem não encontrada."
    end
  end

  private

  # -- Find by slug or id (FriendlyId handles both) ----------------------
  def set_screw
    # // If you have FriendlyId:
    @screw = Screw.friendly.find(params[:id])
    # // If FriendlyId wasn’t loaded for any reason, fallback:
  rescue ActiveRecord::RecordNotFound
    @screw = Screw.find(params[:id])
  end

  # -- Strong params ------------------------------------------------------
  # // Permit all admin-editable fields.
  # // images: [] allows uploading multiple files at once.
  def screw_params
    params.require(:screw).permit(
      :description,
      :thread,
      :thread_length,
      :resistance_class,
      :surface_treatment,
      :automaker,
      :model,
      :price,
      :stock,
      images: [] # // multiple attachments
    )
  end
end
