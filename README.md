# Probar y Proteger los Endpoints de la API Rails con JWT y Postman

> This is a personal translation of the following article: [__Testing and Securing Rails API Endpoints With JWT and Postman__](https://www.microverse.org/blog/testing-and-securing-rails-api-endpoints-with-jwt-and-postman) for [___Uduak Essien___](https://www.microverse.org/blog-authors/uduak-essien)

Este articulo una continuación de [_How to Build a RESTful API Authentication With JWT (TDD Approach)_](https://www.microverse.org/blog/build-a-restful-api-authentication-with-jwt)

---
## Autenticar solicitudes de API
Actualmente el archivo _user_representer.rb_
```ruby
# app/representers/user_representer.rb
class UserRepresenter
# ...
  def as_json
    {
      id: user.id,
      username: user.username,
      token: AuthenticationTokenService.call(user.id)
    }
  end
# ...
end
```

Comencemos agregando un método privado para extraer el token para cada encabezado de solicitud y verificarlo con el usuario que inició sesión.
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API 
include Response 
include ExceptionHandler 
private 
def payload 
  auth_header = request.headers['Authorization']  
  token = auth_header.split(' ').last   
 AuthenticationTokenService.decode(token) 
rescue StandardError   
 nil 
 end
end
```

Agreguemos otro método auxiliar que generará mensajes de autenticación no válidos para solicitudes de inicio de sesión no válidas.
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
[...]
 private
[...]
 def invalid_authentication
   render json: { error: 'You will need to login first' }, status: :unauthorized
 end
end


```

A continuación, agregaremos el método `current_user`. Notará que estamos extrayendo el ID de usuario del método `payload` que agregamos anteriormente.

```ruby
def current_user!
   @current_user = User.find_by(id: payload[0]['user_id'])
 end
 ```

Finalmente, agreguemos el método `authenticate_request` que usaremos en cualquier controlador que deseemos proteger su punto final.

El código final de nuestro controlador de aplicaciones debería verse así ahora:
```ruby
class ApplicationController < ActionController::API
include Response
 include ExceptionHandler
 rescue_from ActiveRecord::RecordNotDestroyed, with: :not_destroyed
 def authenticate_request!
   return invalid_authentication if !payload || !AuthenticationTokenService.valid_payload(payload.first)
   current_user!
   invalid_authentication unless @current_user
 end
 def current_user!
   @current_user = User.find_by(id: payload[0]['user_id'])
 end
 private
 def payload
   auth_header = request.headers['Authorization']
   token = auth_header.split(' ').last
   AuthenticationTokenService.decode(token)
 rescue StandardError
   nil
 end
 def invalid_authentication
   render json: { error: 'You will need to login first' }, status: :unauthorized
 end
end
```

Notarás que agregué `rescate_de ActiveRecord::RecordNotDestroyed`, con `::not_destroyed`. Esta excepción nos ayudará a evitar cualquier error que se produzca cuando tengamos un método de destrucción fallido.

¡Ahora que nuestra solicitud de autenticación! está listo, podemos usar el filtro before_action en cualquier controlador que queramos para proteger su punto final. Justo antes de eso, encendamos nuestro servidor (servidor de rieles) y asegurémonos de que todo funcione como se espera antes de asegurar los puntos finales de los libros.

---
## Protección de nuestros API Endpoints
Dado que las API se vuelven fundamentales para el desarrollo de aplicaciones modernas, la superficie de ataque aumenta continuamente. 

La superficie de ataque en este contexto se refiere a; todos los puntos de entrada a través de los cuales un atacante podría obtener acceso no autorizado a una red o sistema para extraer o ingresar datos o para llevar a cabo otras actividades maliciosas.

Debbie Walkowski en [_Securing APIs: 10 Best Practices for Keeping Your Data and Infrastructure Safe_](https://www.f5.com/labs/articles/education/securing-apis--10-best-practices-for-keeping-your-data-and-infra) proporciona información valiosa sobre este tema.

Comenzaremos agregando `before_action :authenticate_request!` para proteger los _endpoints_ de nuestros libros.
```ruby
# app/controllers/api/v1/books_controller.rb
module Api
 module V1
   class BooksController < ApplicationController
     before_action :authenticate_request!
     before_action :set_book, only: %i[update show destroy]
    [...]
   end
 end
end
```

Si intentamos obtener todos los libros usando nuestro punto final _GET api/v1/books_ (`http://localhost:3000/api/v1/books`) con Postman nuevamente, obtenemos un `"error": "You will need to login first"`.

Eso es bueno, significa nuestra `authenticate_request!` hace exactamente lo que debe hacer.

Ahora, todas las pruebas relacionadas con los _endpoints_ de libros deberían fallar. Intentaremos solucionarlo proporcionando un token en el encabezado de autorización para cada una de nuestras solicitudes al punto final de los libros.

Utiliza un token de portador, una cadena críptica, generalmente generada por el servidor en respuesta a una solicitud de inicio de sesión. El cliente debe enviar este `token` en el `Authorization header` al realizar solicitudes a recursos protegidos.

Primero, creemos un usuario de prueba dentro de nuestro _books_request_spec.rb_ 
```ruby
# rspec spec/requests/books_request_spec.rb
 let(:user) { FactoryBot.create(:user, username: 'acushla', password: 'password') }
```

Luego introduzca encabezados de autorización a cada una de nuestras solicitudes.
```ruby
# spec/requests/books_request_spec.rb
require 'rails_helper'
RSpec.describe 'Books', type: :request do
 [...]
 let(:user) { FactoryBot.create(:user, username: 'acushla', password: 'password') }
 describe 'GET /books' do
   before { get '/api/v1/books', headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
   [...]
 end
 describe 'GET /books/:id' do
   before { get "/api/v1/books/#{book_id}", headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
   [...]
 end
 describe 'POST /books/:id' do
   [...]
   context 'when request attributes are valid' do
     before { post '/api/v1/books', params: valid_attributes, headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
     [...]
   end
   context 'when an invalid request' do
     before { post '/api/v1/books', params: {}, headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
     [...]
   end
 end
 describe 'PUT /books/:id' do
   [...]
   before { put "/api/v1/books/#{book_id}", params: valid_attributes, headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
   [...]
 end
 describe 'DELETE /books/:id' do
   before { delete "/api/v1/books/#{book_id}", headers: { 'Authorization' => AuthenticationTokenService.call(user.id) } }
   [...]
 end
end
```

Ejecutemos nuestra prueba nuevamente. Todo debería estar funcionando bien ahora.
```sh
rspec spec/requests/books_request_spec.rb
```

Antes de continuar y probar esto con Postman, debemos actualizar nuestro controlador de libros, de modo que usemos el usuario actual para la operación de creación de libros.
```ruby
# app/controllers/api/v1/books_controller.rb
def create
  @book = current_user!.books.create(book_params)
  if @book.save
    [...]
  end
end
```

Gracias a esto, ya no necesitaremos el atributo `user_id` dentro de nuestra solicitud `POST`.
```ruby
# spec/requests/books_request_spec.rb
describe 'POST /books/:id' do
   [...]
   let(:valid_attributes) do
     { title: 'Whispers of Time', author: 'Dr. Krishna Saksena',
       category_id: history.id }
   end
  [...]
end
```

Después de esta guía paso a paso, debería sentirse más cómodo asegurando cualquiera de sus terminales. 

Además, si va a utilizar _devise_ en el futuro, debe consultar la [documentación](https://github.com/waiting-for-dev/devise-jwt).

# Probando y documentando nuestros endpoints
Aquí, vamos a construir y organizar todos nuestros _endpoints_ en una sola colección usando Postman. Lo usaremos para generar documentación.

Para agregar una colección, vea la imagen a continuación: