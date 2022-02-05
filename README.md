# Cómo Crear una Autenticación de API RESTful con JWT (Enfoque TDD)
> This is a personal translation of the following article: [__How to Build a RESTful API Authentication With JWT (TDD Approach)__](https://www.microverse.org/blog/build-a-restful-api-authentication-with-jwt) for [___Uduak Essien___](https://www.microverse.org/blog-authors/uduak-essien)

Este articulo una continuación de [_Test Driven Development of a RESTful JSON API With Rails_](https://www.microverse.org/blog/test-driven-development-of-restful-json-api-with-rails)

---
## Configurando Nuestras Dependencias de Gemas
Primero, cubriremos la autenticación simple usando la gema [bcrypt](https://github.com/bcrypt-ruby/bcrypt-ruby) y una autenticación basada en token:  JSON Web Token authentication ([__JWT__](https://github.com/jwt/ruby-jwt)). La autenticación basada en token no almacena nada en el servidor. Más bien, crea un token codificado único que se verifica cada vez que se realiza una solicitud. También es _sin estado_.

La siguiente tabla muestra la lista de nuestros _API Endpoints_.  
[EndpointsAPI](ima/EndpointsAPI.png)

Necesitaremos las siguientes gemas en nuestro _Gemfile_, que puede agregar en la parte inferior:
- `bcrypt`: un algoritmo hash sofisticado y seguro diseñado por el proyecto _OpenBSD_ para cifrar contraseñas. La gema bcrypt Ruby proporciona un envoltorio simple para manejar contraseñas de manera segura.
- `jwt`: una implementación Ruby pura del estándar RFC 7519 OAuth JSON Web Token.
- `rack-cors`: proporciona soporte para Cross-Origin Resource Sharing (CORS) para aplicaciones web compatibles con Rack.

Instale las gemas ejecutando `bundle install`.

---
## Configuración de modelos y migración
Comencemos generando nuestro modelo de usuario y actualizando nuestro modelo de libro para incluir la ID de usuario como clave externa. Esto significa que para cada libro creado, necesitaremos identificar qué usuario lo agregó.
```sh
rails g model User username password_digest
rails g migration update_books_table
```
La gema BCrypt requiere que tengamos un atributo `XXX_digest`, en nuestro caso `password_digest`. Agregar el método `has_secure_password` en nuestro modelo de usuario establecerá y se autenticará con una contraseña de BCrypt. Su modelo de usuario ahora debería verse así:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password
end
```
Al archivo de migración de su usuario le debe gustar el siguiente código.
```ruby
# db/migrate/[timestamp]_create_users.rb
class CreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users do |t|
      t.string :username
      t.string :password_digest
      t.timestamps
    end
  end
end
```
Actualice el archivo de migración de libros generado *[timestamp]_update_books.rb* para que tenga este aspecto:
```ruby
# db/migrate/[timestamp]_update_books.rb
class UpdateBooksTable < ActiveRecord::Migration[6.1]
  def change
    add_reference :books, :user, foreign_key: true
  end
end
```

Ejecutemos las migraciones:
```sh
rails db:migrate
```

Escribamos las especificaciones del modelo para el modelo de usuario:
```ruby
# spec/models/user_spec.rb
require 'rails_helper'
RSpec.describe User, type: :model do
  it { should validate_presence_of(:username) }
  it { should validate_uniqueness_of(:username) }
  it {
    should validate_length_of(:username)
      .is_at_least(3)
  }
  it { should validate_presence_of(:password) }
  it {
    should_not validate_length_of(:password)
      .is_at_least(5)
  }
  describe 'Associations' do
    it { should have_many(:books) }
  end
end
```
Ahora, intente ejecutar las especificaciones ejecutando:
```sh
rspec spec/models/user_spec.rb
```

Tal como se esperaba, hemos fallado las pruebas. Solo uno ha pasado debido al `has_secure_password` que agregamos. 

Sigamos adelante y solucionemos las fallas:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password
  has_many :books
  validates :username, presence: true, uniqueness: true, length: { minimum: 3 }
  validates :password, presence: true, length: { minimum: 6 }
end
```

Ahora, podemos ejecutar las pruebas de nuevo. Deberías ver que todas las pruebas han sido aprobadas.

Recuerda que actualizamos nuestra columna de tabla de libros. Entonces, actualicemos nuestro archivo _book_specs_ para reflejar la asociación de usuarios actualizando las pruebas de asociación.
```ruby
#spec/models/book_spec.rb
RSpec.describe Book, type: :model do
  # Association test
  it { should belong_to(:category) }
  it { should belong_to(:user) }
  # ...
end
```
Arriba, es obvio que ejecutar las pruebas _rspec spec/models/book_spec.rb_ resultará en una prueba fallida. Podemos arreglar esto fácilmente agregando la  asociación `belong_to` al modelo del libro.
```ruby
#app/models/book.rb
class Book < ApplicationRecord
  belongs_to :category
  belongs_to :user
  validates :title, :author, presence: true, length: { minimum: 3 }
end
```

---
## Controladores
> _Los controladores juegan un papel vital en el patrón del marco MVC. Actúan como intermediarios entre las vistas y el modelo. Cada vez que un usuario realiza una solicitud, se crea un objeto (instancia del controlador), y cuando se completa la solicitud, el objeto se destruye._

Ya que no crearemos más modelos para este proyecto, sigamos adelante y generemos los controladores. Tanto un controlador de usuario como un controlador de autenticación se utilizarán para manejar la autenticación. Puede considerarlo como su controlador de sesiones habitual.
```sh
rails g controller Users \
  && rails g controller Authentication
```

Siguiendo nuestro enfoque de control de versiones de API, vamos a mover los archivos de controlador generados a app/controllers/api/v1:
```sh
mv app/controllers/{users_controller.rb,authentication_controller.rb} app/controllers/api/v1/
```

Antes de escribir nuestras primeras pruebas en esta parte, agreguemos el _factory_ para usuarios y actualicemos el de libros (_books_request_spec_ está fallando).
```sh
rspec spec/requests/books_request_spec.rb
```
> NOTA: Dependiendo la versión de la gema `rspec-rails`, es posible los archivos del directorio _spec/requests/_, se generaron con el nombre *books_spec.rb* en lugar de *books_request_spec.rb*

```sh
touch spec/factories/user.rb
```

```ruby
# spec/factories/user.rb
FactoryBot.define do
  factory :user do
    username { Faker::Internet.username(specifier: 5..10) }
    password { 'password' }
  end
end
```

Ahora podemos actualizar el _factory_ de libros agregando `user { create(:user) }` similar a lo que hicimos con la categoría.
```ruby
# spec/factories/book.rb
FactoryBot.define do
  factory :book do
    title { Faker::Book.title }
    author { Faker::Book.author }
    category { create(:category) }
    user { create(:user) }
  end
end
```

Ejecute `rspec spec/requests/books_request_spec.rb` nuevamente y todas las pruebas deberían pasar ahora.

> NOTA: Ademas de modificar *spec/requests/books_request_spec.rb* también es necesario modificar el método `book_params` del archivo *app/controllers/api/v1/books_controller.rb* para que acepte el `user_id`.

Ahora, escribamos las especificaciones para _/register_ y _/login_  API:
```ruby
# spec/requests/users_request_spec.rb
RSpec.describe 'Users', type: :request do
  describe 'POST /register' do
    it 'authenticates the user' do
      post '/api/v1/register', params: { user: { username: 'user1', password: 'password' } }
      expect(response).to have_http_status(:created)
      expect(json).to eq({
                           'id' => User.last.id,
                           'username' => 'user1',
                           'token' => AuthenticationTokenService.call(User.last.id)
                         })
    end
  end
end
```

```ruby
# spec/requests/authentication_request_spec.rb
RSpec.describe 'Authentications', type: :request do
  describe 'POST /login' do
    let(:user) { FactoryBot.create(:user, username: 'user1', password: 'password') }
    it 'authenticates the user' do
      post '/api/v1/login', params: { username: user.username, password: 'password' }
      expect(response).to have_http_status(:created)
      expect(json).to eq({
                           'id' => user.id,
                           'username' => 'user1',
                           'token' => AuthenticationTokenService.call(user.id)
                         })
    end
    it 'returns error when username does not exist' do
      post '/api/v1/login', params: { username: 'ac', password: 'password' }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq({
                           'error' => 'No such user'
                         })
    end
    it 'returns error when password is incorrect' do
      post '/api/v1/login', params: { username: user.username, password: 'incorrect' }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq({
                           'error' => 'Incorrect password '
                         })
    end
  end
end
```

Lo que hará el servicio `AuthenticationTokenService`, como su nombre lo indica, es generar un token para cada usuario.

Continuando, ejecutar nuestras especificaciones `rspec spec/requests/users_request_spec.rb && rspec spec/requests/authentication_request_spec.rb` generará un  `ActionController::RoutingError`. Entonces, arreglemos eso rápidamente.

Aquí necesitaremos solo dos rutas _/login_ y _/register_. Nuestro _/config/routes_ ahora debería verse así:
```ruby
# config/routes
get 'users/Authentication'
  namespace :api do
    namespace :v1 do
      resources :categories, only: %i[index create destroy]
      resources :books, only: %i[index create show update destroy]
      post 'login', to: 'authentication#create'
      post 'register', to: 'users#create'
    end
  end
end
```

Ahora ejecute `rspec spec/requests/users_request_spec.rb && rspec spec/requests/authentication_request_spec.rb` nuevamente. El siguiente error debería ser `…..define constant Api::V1::UsersController, but didn't.`.

Envolvamos la clase `UsersController` con el módulo `API` y `V1`, luego agreguemos el método `#create`  a nuestro `users_controller`. Puedes hacer esto así:
```ruby
# app/controllers/api/v1/users_controller.rb
module Api
  module V1
    class UsersController < ApplicationController
      def create
        user = User.create(user_params)
        if user.save
          render json: UserRepresenter.new(user).as_json, status: :created
        else
          render json: { error: user.errors.full_messages.first }, status: :unprocessable_entity
        end
      end
      private
      def user_params
        params.require(:user).permit(:username, :password)
      end
    end
  end
end
```

También envolvamos la clase `AuthenticationController` con el módulo `API` y `V1`, luego agreguemos el método `#create` para la autenticación.
```ruby
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
```

```ruby
# app/controllers/api/v1/users_controller.rb
module Api
 module V1
   class AuthenticationController < ApplicationController
     class AuthenticateError < StandardError; end
     rescue_from ActionController::ParameterMissing, with: :parameter_missing
     rescue_from AuthenticateError, with: :handle_unauthenticated
     def create
       if user
         raise AuthenticateError unless user.authenticate(params.require(:password))
         render json: UserRepresenter.new(user).as_json, status: :created
       else
         render json: { error: 'No such user' }, status: :unauthorized
       end
     end
     private
     def user
       @user ||= User.find_by(username: params.require(:username))
     end
     def parameter_missing(error)
       render json: { error: error.message }, status: :unprocessable_entity
     end
     def handle_unauthenticated
       render json: { error: 'Incorrect password ' }, status: :unauthorized
     end
   end
 end
end
```

Es posible que recuerde nuestro propio asistente personalizado del artículo anterior. Lo usamos para representar la respuesta JSON tal como la queríamos. Avancemos y creemos uno para los usuarios aquí:
```ruby
touch app/representers/user_representer.rb
# app/representers/user_representer.rb
class UserRepresenter
  def initialize(user)
    @user = user
  end
  def as_json
    {
      id: user.id,
      username: user.username,
      token: AuthenticationTokenService.call(user.id)
    }
  end
  private
  attr_reader :user
end
```

---
## Servicio de Token de Autenticación
>Es una buena práctica mantener nuestros controladores Rails limpios y SECOS. Poner un solo objeto de servicio en la carpeta de servicios le permite ser un poco más granular. El artículo de Tomek Pewiński, [_How Service Objects in Rails Will Help You Design Clean And Maintainable Code,_](https://www.netguru.com/blog/service-objects-in-rails), arroja más luz sobre este tema.

Comenzaremos creando un directorio de _services_ y un archivo _authentication_token_service.rb_.  
Nuestra clase de servicio de token vivirá en el directorio de _services_ en el directorio _./app_ y solo manejará una sola tarea generando token para nuestros usuarios autenticados.
```sh
mkdir app/services && touch app/services/authentication_token_service.rb
```

A continuación, genere la `SECRET_KEY` que se utilizará para codificar y decodificar nuestro token.
```ruby
# app/services/authentication_token_service.rb
class AuthenticationTokenService
  HMAC_SECRET = Rails.application.secrets.secret_key_base
end
```
A continuación, tomaremos el ID de usuario y el tiempo de caducidad como `payload`.
```ruby
# app/services/authentication_token_service.rb
class AuthenticationTokenService
  HMAC_SECRET = Rails.application.secrets.secret_key_base
  ALGORITHM_TYPE = 'HS256'.freeze
  def self.call(user_id)
    exp = 24.hours.from_now.to_i
    payload = { user_id: user_id, exp: exp }
    JWT.encode payload, HMAC_SECRET, ALGORITHM_TYPE
  end
  def self.decode(token)
    JWT.decode token, HMAC_SECRET, true, { algorithm: ALGORITHM_TYPE }
  rescue JWT::ExpiredSignature, JWT::DecodeError
    false
  end
  def self.valid_payload(payload)
    !expired(payload)
  end
  def self.expired(payload)
    Time.at(payload['exp']) < Time.now
  end
  def self.expired_token
    render json: { error: 'Expired token! login again' }, status: :unauthorized
  end
end
```
Ahora, ejecutemos todas las pruebas nuevamente para asegurarnos de que todo esté en verde.
```sh
bundle exec rspec
```

Como puede ver, tuve una prueba fallida, _"Expected the response to have status code 201, but it was 422"_.  
La línea 47 de _books_request_specs.rb_, donde escribimos las especificaciones para publicar un nuevo libro, es donde tenemos el error. Esto se debe a que nuestra aplicación se ha modificado para vincular cada libro nuevo a un usuario. Podemos solucionarlo rápidamente agregando un usuario a los parámetros del libro posterior, así como al de `books_controller`.
```ruby
let!(:user1) { create(:user) }
   let(:valid_attributes) do
     { title: 'Whispers of Time', author: 'Dr. Krishna Saksena',
       category_id: history.id, user_id: user1.id }
   end
[....]
```

```ruby
# app/controllers/api/v1/books_controller.rb
[....]
     def book_params
       params.permit(:title, :author, :category_id, :user_id)
     end
[....]
```

Vuelva a ejecutar las pruebas. Ahora todo debería ser verde.

---
## Conclusion‍
Así es como autenticamos una API RESTful JSON usando TDD.  
Un enfoque de desarrollo basado en pruebas con una buena cobertura de pruebas nos permite tener una imagen completa de la característica que estaríamos desarrollando, así como sus requisitos para que esas pruebas pasen.  

Continúa en [_Testing and Securing Rails API Endpoints With JWT and Postman_](https://www.microverse.org/blog/testing-and-securing-rails-api-endpoints-with-jwt-and-postman)