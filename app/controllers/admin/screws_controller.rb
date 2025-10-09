class Admin::ScrewsController < ApplicationController
  before_action :require_admin_basic_auth

  # // Find by slug OR numeric id (FriendlyId handles both)
  before_action :set_screw, only: [:edit, :update]

  # == LIST ===============================================================
  def index
    # // Basic search & sorting (same as your version)
    @q   = params[:q].to_s.strip
    @sort = params[:sort].presence_in(%w[created_at price stock automaker model]) || "created_at"
    @dir  = params[:dir].presence_in(%w[asc desc]) || "desc"

    scope = Screw.all
    if @q.present?
      # // ILIKE works on Postgres; in SQLite dev it behaves as case-insensitive LIKE
      scope = scope.where("description ILIKE :q OR automaker ILIKE :q OR model ILIKE :q", q: "%#{@q}%")
    end

    @screws = scope.order(Arel.sql("#{@sort} #{@dir}"))
                   .limit(300)
                   .includes(images_attachments: :blob)
  end

  # == EDIT ===============================================================
  def edit
    # // @screw is set by set_screw
  end

  # == UPDATE =============================================================
  def update
    # // Only stock is editable here (as in your version)
    if @screw.update(screw_params)
      redirect_to admin_screws_path, notice: "Estoque atualizado para #{@screw.stock}."
    else
      flash.now[:alert] = "Não foi possível atualizar o estoque."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # // FriendlyId-aware finder
  def set_screw
    @screw = Screw.friendly.find(params[:id])  # // accepts slug or id
  end

  def screw_params
    params.require(:screw).permit(:stock)      # // only stock is editable
  end
end
