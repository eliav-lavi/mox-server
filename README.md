# mox-server

**mox** is an easy-to-use mock server aimed at facilitating local development & testing scenarios. To support this, mox allows to dynamically create & manipulate endpoints on its server. The created mock endpoints are available at the same port mox is running at.

## Setup
If you're using Docker, the simplest way to get started is with `docker-compose up -d`. This will bring up the server itself at port `9898`. 

## Usage
NOTE: [mox-ui](https://github.com/eliav-lavi/mox-ui) is recommended for easy manual management of mox. Should you need to call the server API directly (e.g. in a testing scenario), you may use the following abilities.

### Create a New Endpoint
To declare a new mock endpoint, `POST` to `/endpoint`. The request body may look like this:
```json
{
  "verb": "GET",
  "path": "/my_path",
  "return_value": "{\"a\": 4}"
}
```
Note that the `return_value` must be a string - you should escape anything that goes in it, should you need to, as demonstrated in the example above.

After creation, the declared endpoint will be assigned a unique id by mox, which will be present in the response  from `POST /endpoint`.

### List All Endpoints
To list all existing endpoints, call `GET` on `/endpoint`.

### Update an Existing Endpoint
To update an existing endpoint, call `PUT` on `/endpoint`. The request body should contain the `id` of the endpoint, in addition to the endpoint information:
```json
{
  "id": 3,
  "verb": "POST",
  "path": "/my_new_path",
  "return_value": "[1,2,3]"
}
```

### Delete an Existing Endpoint
To delete an existing endpoint, call `DELETE` on `/endpoint` and pass the id of the endpoint to be deleted as a parameter: `DELETE /endpoint?id=3`

### Batch Actions
To create multiple endpoints in a single call, use `POST /endpoints` with an array of endpoints in the request body:
```json
[
  {
    "verb":"GET",
    "path":"/foo",
    "return_value":"{\"hello\": \"world\"}"
  },
  {
    "verb":"POST",
    "path":"/bar",
    "return_value":"[1,2,3]"
  }
]
```

To delete all existing endpoints, call `DELETE endpoints`

## Templating & Dynamic Responses
Sometimes more sophisticated mocks are required - one might need to build the mocked response dynamically, based on the parameters or request body sent to the endpoint. To support that, mox allows the `return_value` to be written as a Ruby [ERB](https://docs.ruby-lang.org/en/2.6.0/ERB.html) template. The variables `params` & `body` are exposed by mox to allow access to the query params and the request body, respectively.

Let's examine a few concrete examples.

### Working With Query Params
Call `POST /endpoint` with this request body:
```json
{
  "verb": "GET",
  "path": "/test-params",
  "return_value": "{\"full_name\": \"<%= params['first-name'] %> <%= params['last-name'] %>\"}"
}
```
Then, call the server at `GET /test-params?first-name=John&last-name=Doe`. You should be responded with the following JSON:
```json
{
  "full_name": "John Doe"
}
```
### Working With Request Body
Call `POST /endpoint` with this request body:
```json
{
  "verb": "POST",
  "path": "/test-body",
  "return_value": "{\"unique_city\": \"<%= body['city'] %>, <%= body['state'] %>, <%= body['country'] %>\"}"
}
```
Then, call the server at `POST /test-body` with the following request body:
```json
{
  "city": "London",
  "state": "Ontario",
  "country": "Canada"
}
```

You should be responded with the following JSON:
```json
{
  "unique_city": "London, Ontario, Canada"
}
```

### Using Control Flow
You can also control the entire structure of the mocked response.
Call `POST /endpoint` with this request body:
```json
{
  "verb": "GET",
  "path": "/test-control-flow",
  "return_value": "{\"greeting\": <% if params['age'].to_i > 18 %> \"Hello, adult\" <% else %> \"Hello!\" <% end %>}"
}
```
Then, call the server at `GET /test-control-flow?age=19`. You should be responded with the following JSON:
```json
{
  "greeting": "Hello, adult"
}
```
However, calling `GET /test-control-flow?age=17` should give back 
```json
{
  "greeting": "Hello!"
}
```

## Controlling Response Times
It is possible to set a fixed delay time before an `endpoint` returns its `return_value` by supplying the optional `min_response_millis`:
```json
{
  "verb": "GET",
  "path": "/my_delayed_path",
  "return_value": "{\"a\": 4}",
  "min_response_millis": 150
}
```
The value should be expressed in **milliseconds**.

It is also possible to set a range for randomizing the delay time by supplying `max_response_millis` in addition to `min_response_millis`:
```json
{
  "verb": "GET",
  "path": "/my_delayed_path_2",
  "return_value": "{\"a\": 4}",
  "min_response_millis": 150,
  "max_response_millis": 500,
}
```