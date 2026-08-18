# db/seeds_users.rb
#
# Synthetic user data for local development. Kept separate from db/seeds.rb on purpose:
# that file seeds the catalog (22 screws) and mixing accounts into it would change what
# `bin/rails db:seed` means. Run this one explicitly:
#
#   bin/rails runner db/seeds_users.rb
#
# Why this file exists: the development database has had zero users since the catalog
# seed was added, which is what blocked Flow 1 (authentication) from being validated
# during the Rails 8.0 and 8.1 upgrades. See UPGRADE_PLAN.md Etapa D1 step 10 and
# Etapa E step 8. The Devise 5.0 upgrade (Etapa F) touches authentication directly, so
# the flow has to be walkable both before and after — see DEVISE_50_MIGRATION.md §7.
#
# Two accounts, because ApplicationController#ensure_first_address_created redirects any
# signed-in user with no address to the address form. With only one account it is easy to
# misread that redirect as an authentication failure; with both, the difference is visible:
#
#   confirmado@dev.local     has an address  -> browses freely
#   sem-endereco@dev.local   has no address  -> bounced to /shipping_addresses/new
#
# Both are created already confirmed (User declares :confirmable), so they can sign in
# without going through the mailer. Testing the confirmation email itself means signing up
# a fresh account through the UI and opening /letter_opener — that is a separate step of
# the flow and deliberately not seeded here.
#
# Safe to re-run: accounts are matched by email, and the password is only rewritten when it
# does not already match, so a second run is a no-op.

unless Rails.env.development? || Rails.env.test?
  abort("db/seeds_users.rb is development/test only — refusing to run in #{Rails.env}.")
end

PASSWORD = "password123".freeze  # same password the test fixtures use

USERS = [
  {
    email: "confirmado@dev.local",
    name: "Dev Confirmado",
    address: {
      recipient_name: "Dev Confirmado",
      cep: "01310-100",
      street: "Avenida Paulista",
      number: "1000",
      complement: "Conjunto 101",
      district: "Bela Vista",
      city: "São Paulo",
      state: "SP"
    }
  },
  {
    email: "sem-endereco@dev.local",
    name: "Dev Sem Endereço",
    address: nil
  }
].freeze

USERS.each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])

  if user.new_record?
    user.assign_attributes(name: attrs[:name], password: PASSWORD)
    # Sets confirmed_at and suppresses the confirmation email. Must run before save.
    user.skip_confirmation!
    user.save!
    puts "  created user #{user.email}"
  else
    # Converge without rewriting on every run: bcrypt would produce a new hash each time.
    unless user.valid_password?(PASSWORD)
      user.password = PASSWORD
      user.save!
      puts "  reset password for #{user.email}"
    end

    # A user seeded before this guard existed, or confirmed manually, may still be pending.
    user.confirm unless user.confirmed?

    puts "  user #{user.email} already present"
  end

  next if attrs[:address].nil?

  # ShippingAddress#set_default_if_first marks the first address as default on its own,
  # and a unique partial index enforces one default per user — nothing to set here.
  address = user.shipping_addresses.find_or_initialize_by(cep: attrs[:address][:cep],
                                                          number: attrs[:address][:number])
  if address.new_record?
    address.assign_attributes(attrs[:address])
    address.save!
    puts "  created address for #{user.email} (default: #{address.is_default})"
  else
    puts "  address for #{user.email} already present"
  end
end

puts
puts "Users: #{User.count} | confirmed: #{User.where.not(confirmed_at: nil).count} | addresses: #{ShippingAddress.count}"
puts "Sign in with any of the emails above and the password: #{PASSWORD}"
