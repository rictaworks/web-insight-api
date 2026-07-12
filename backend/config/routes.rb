Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'

  namespace :api do
    namespace :v1 do
      post 'auth/google', to: 'auth#google'
      post 'events/collect', to: 'events#collect'

      resources :sites, only: %i[index create show] do
        member do
          get :snippet
          get :pageviews
          get :heatmap
          get :performance
          get :retention
          post :recommend
        end
        resources :funnels, only: %i[index create show]
        resources :alert_rules, only: %i[index create update]
      end

      namespace :admin do
        resources :sites, only: [:index] do
          member do
            post :reset_ai
          end
        end
        resources :users, only: %i[index show]
        resource :bot_rules, only: [:update]
      end
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
