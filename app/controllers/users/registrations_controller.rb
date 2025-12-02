class Users::RegistrationsController < Devise::RegistrationsController
  protected

  # // After successful signup, force the user to create their first address
  # // We pass return_to=checkout so the flow bounces back nicely.
  def after_sign_up_path_for(resource)
    new_shipping_address_path(return_to: "checkout")
  end

  # // If using Devise Confirmable, same redirect after signup (inactive)
  def after_inactive_sign_up_path_for(resource)
    root_path  # // ou new_user_session_path, ou outra página pública
  end
end
