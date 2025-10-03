Rails.application.routes.draw do
  root to: "pages#home"

  resources :screws, only: [:index, :show]

  # // A single cart (not per-id), stored in the session
  resource :cart, only: [:show] do
    post   "add/:screw_id",    to: "carts#add",    as: :add
    patch  "set/:screw_id",    to: "carts#set",    as: :set
    delete "remove/:screw_id", to: "carts#remove", as: :remove
    delete "clear",            to: "carts#clear",  as: :clear
  end

  # // Orders: new (checkout), create, show (confirmation)
  resources :orders, only: [:new, :create, :show]
  get "/checkout", to: "orders#new", as: :checkout # // pretty alias


    # ViaCEP lookup endpoint
  # // Example: GET /cep/01311-000 → JSON like {street, district, city, state, cep}
  # // We set a JSON default so you can call it easily from JS.
  get "/cep/:cep", to: "cep#lookup", defaults: { format: :json }, as: :cep_looku


  # // Admin (basic auth; no user system yet)
  namespace :admin do
    get 'screws/index'
    get 'screws/edit'
    get 'screws/update'
    root to: "orders#index"
    resources :orders, only: [:index, :show, :update]

    # // Add a small CRUD just for stock (index + edit + update)
    resources :screws, only: [:index, :edit, :update]
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
end
