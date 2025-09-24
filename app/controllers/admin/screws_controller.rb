class Admin::ScrewsController < ApplicationController
  def index
    # // Basic search & sorting (optional nicety)
    @q = params[:q].to_s.strip
    @sort = params[:sort].presence_in(%w[created_at price stock automaker model]) || "created_at"
    @dir  = params[:dir].presence_in(%w[asc desc]) || "desc"

    scope = Screw.all
    scope = scope.where("description ILIKE :q OR automaker ILIKE :q OR model ILIKE :q", q: "%#{@q}%") if @q.present?

    @screws = scope.order(Arel.sql("#{@sort} #{@dir}")).limit(300).includes(images_attachments: :blob)
  end

  # // GET /admin/screws/:id/edit
  def edit
    @screw = Screw.find(params[:id])  # // sets @screw → edit view uses it
  end

  # // PATCH /admin/screws/:id
  def update
    @screw = Screw.find(params[:id])

    # // Permit only stock to avoid accidental field edits
    if @screw.update(screw_params)
      redirect_to admin_screws_path, notice: "Estoque atualizado para #{@screw.stock}."
    else
      flash.now[:alert] = "Não foi possível atualizar o estoque."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def screw_params
    params.require(:screw).permit(:stock)  # // only stock is editable here
  end
end
