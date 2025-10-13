module ImagesHelper
  def cdn_variant(source, **opts)
    # // Normalize to a Blob
    blob = source.respond_to?(:blob) ? source.blob : source
    return unless blob.is_a?(ActiveStorage::Blob)

    if cloudinary_service?
      base = opts.slice(:resize_to_limit, :resize_to_fit, :resize_to_fill)
      blob.variant(base.merge(fetch_format: :auto, quality: "auto"))
    else
      # // Local disk: just return the original file (no variant -> no processor needed)
      blob
    end
  end

  def primary_attachment(record)
    # attachments have created_at; use the newest
    record.images.attachments.max_by(&:created_at)
  end

  private

  def cloudinary_service?
    ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::CloudinaryService)
  rescue NameError
    false
  end
end
