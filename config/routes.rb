Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"

  resources :screws, only: [:index, :show]

  # // A single cart (not per-id), stored in the session
  resource :cart, only: [:show] do
    post   "add/:screw_id",    to: "carts#add",    as: :add
    patch  "set/:screw_id",    to: "carts#set",    as: :set
    delete "remove/:screw_id", to: "carts#remove", as: :remove
    delete "clear",            to: "carts#clear",  as: :clear
  end

  # Orders: checkout/new/create/show + collection route "mine"
  resources :orders, only: [:new, :create, :show] do
    collection do
      get :mine, as: :my_orders  # // now the helper is my_orders_path
    end
  end

  get "/checkout", to: "orders#new", as: :checkout

  # ✅ This creates `my_orders_path` → /orders/mine
  get "/orders/mine", to: "orders#mine", as: :my_orders

    # ViaCEP lookup endpoint
  # // Example: GET /cep/01311-000 → JSON like {street, district, city, state, cep}
  # // We set a JSON default so you can call it easily from JS.
  get "/cep/:cep", to: "cep#lookup", defaults: { format: :json }, as: :cep_looku


  # // Admin area
  namespace :admin do
    root to: "orders#index"  # if you already have another root here, keep it

    # Orders already exist…
    resources :orders, only: [:index, :show, :update]

    # Screws CRUD (NEW)
    resources :screws do
      # DELETE /admin/screws/:id/images/:attachment_id
      # // lets the admin remove a single uploaded image from a screw
      member do
        delete :destroy_image
      end
    end
end

  # // Dev-only email viewer (mount at top-level, NOT inside the cart block)
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  # Sitemap (SEO)
  # // Serve XML sitemap at /sitemap.xml
  get "/sitemap.xml", to: "sitemaps#show", defaults: { format: :xml }

  # Stripe Checkout (create a Session)
  # // POST /checkout_sessions?order_id=123
  # // The controller will build a Stripe Checkout Session and redirect.
  post "/checkout_sessions", to: "checkout_sessions#create", as: :checkout_sessions
  post "/stripe/webhooks", to: "stripe_webhooks#receive"
end
