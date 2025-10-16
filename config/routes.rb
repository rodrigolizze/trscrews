Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"

  # Shipping addresses (single source of truth)
  resources :shipping_addresses, only: [:new, :create, :edit, :update, :index, :destroy] do
    member do
      patch :make_default
    end
  end

  resources :screws, only: [:index, :show]

  # Single cart stored in session
  resource :cart, only: [:show] do
    post   "add/:screw_id",    to: "carts#add",    as: :add
    patch  "set/:screw_id",    to: "carts#set",    as: :set
    delete "remove/:screw_id", to: "carts#remove", as: :remove
    delete "clear",            to: "carts#clear",  as: :clear
  end


  # ✅ Explicit “My orders” route + helper: my_orders_path
  get "/orders/mine", to: "orders#mine", as: :my_orders

  # Orders: checkout/new/create/show
  resources :orders, only: [:new, :create, :show]
  get "/checkout", to: "orders#new", as: :checkout

  # ViaCEP lookup endpoint (fix helper name)
  get "/cep/:cep", to: "cep#lookup", defaults: { format: :json }, as: :cep_lookup

  # Admin area
  namespace :admin do
    root to: "orders#index"
    resources :orders, only: [:index, :show, :update]
    resources :screws do
      member do
        delete :destroy_image
      end
    end
  end

  # Dev-only email viewer
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Health
  get "up" => "rails/health#show", as: :rails_health_check

  # SEO sitemap
  get "/sitemap.xml", to: "sitemaps#show", defaults: { format: :xml }

  # Stripe
  post "/checkout_sessions", to: "checkout_sessions#create", as: :checkout_sessions
  post "/stripe/webhooks",   to: "stripe_webhooks#receive"
end
