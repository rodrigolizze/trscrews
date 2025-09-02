class ScrewsController < ApplicationController
  def index
    # Only allow the keys we expect
    filter_params = params.permit(:automaker, :model, :thread, :surface_treatment, :q, :sort)

    # Start with a safe base relation (never nil) and eager-load images
    base = Screw.includes(images_attachments: :blob).apply_filters(filter_params)

    # Apply search if present (our scope already returns a relation even if q is blank)
    base = base.search(filter_params[:q])

    # Simple, whitelisted sort (defaults to newest first)
    base = case filter_params[:sort]
           when "price_asc"  then base.order(price: :asc)
           when "price_desc" then base.order(price: :desc)
           else                   base.order(created_at: :desc)
           end

    # Paginate
    @pagy, @screws = pagy(base)

    # Build distinct options for the filters
    @automakers = Screw.distinct.order(:automaker).pluck(:automaker)
    @models     = Screw.distinct.order(:model).pluck(:model)
    @threads    = Screw.distinct.order(:thread).pluck(:thread)
    @surfaces   = Screw.distinct.order(:surface_treatment).pluck(:surface_treatment)
  end

  def show
    @screw = Screw.find(params[:id])
  end
end
