Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: :index
      resources :categories, only: %i[index create destroy]
      resources :books
      post 'login', to: 'authentication#create'
      post 'register', to: 'users#create'
    end
  end
end
