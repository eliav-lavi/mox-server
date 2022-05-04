# mox-server

**mox** is an easy-to-use mock server aimed at facilitating local development & testing scenarios. To support this, mox allows to dynamically create & manipulate endpoints on its server. The created mock endpoints are available at the same port mox is running at.

## Use Cases

Classic use-cases for using mox is when writing component tests for a microservice, which may be implemented in any language. Instead of bringing up collaboratoring HTTP services, which might be complicate and resource-heavy, mox can help by serving mocked responses instead. Any endpoint defined in mox is fully customizable and updatable, so you can test different scenarios easily.

It is also useful for local development - mox allows spinning up a microservice on its own, without doing the same with its collaborating HTTP services. Along with [mox-ui](https://github.com/eliav-lavi/mox-ui), it is easy to manually adjust the responses of collaborators in order to experience & manually test the difference in the application's behavior.

Needless to say, **mox is not intended to be used in production** or any world-facing environment for obvious security reasons.

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
To update an existing endpoint, call `PUT` on `/endpoint/:id` (replace `:id` with the relevant endpoint id), in addition to the endpoint information:
```json
{
  "id": 3,
  "verb": "POST",
  "path": "/my_new_path",
  "return_value": "[1,2,3]"
}
```

### Delete an Existing Endpoint
To delete an existing endpoint, call `DELETE` on `/endpoint/:id` (replace `:id` with the relevant endpoint id), e.g.: `DELETE /endpoint/3`

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

To delete all existing endpoints, call `DELETE /endpoints`

**NOTE**: in case an undefined endpoint will be called, a special, reserved `492` status code will be returned by mox to indicate this. This is done to allow users to define endpoints which return `404` status codes explicitly.

### Usage Errors
In case of failure during a call to any of the routes in this section, mox will respond with regular status codes:
* `400` - in case the error is due to a client error (e.g. a required field, such as `path` or `return_value` was not supplied)
* `500` - any other error (e.g. some unforeseen server error).

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

**NOTE**: In case ERB fails to evaluate `return_value` due to `SyntaxError` or any `StandardError` (e.g. calling an undefined method), a special, reserved `591` status code will be returned by mox to indicate this. This is done to allow users to define endpoints which return `500` status codes explicitly.
It is your responsibility to make sure the ERB code you supply in a `return_value` is valid; mox cannot validate this upon endpoint creation.


## Further Controls
### Status Code
Supply the optional `status_code` field to set a custom status code for an `endpoint`:
```json
{
  "verb": "GET",
  "path": "/my_missing_resource",
  "return_value": "{}",
  "status_code": 404
}
```

**NOTE**: Any status code is accepted as input, except for two which are reserved by mox:
* `492` - will be returned when an (yet) undefined endpoint gets called
* `491` - will be returned during a call to a defined endpoint when the evaluation of a dynamic template into a concrete response has failed, either by [`SyntaxError`](https://ruby-doc.org/core-2.6.3/SyntaxError.html) or a [`StandardError`](https://ruby-doc.org/core-2.6.3/StandardError.html). 
* `591`- will be returned during a call to a defined endpoint when the evaluation of a dynamic template into a concrete response has failed by some unexpected error (should you encounter this scenario, please report it to maintainers 🙏).

These two status code were picked as they are not [recognized HTTP status codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status), hence the chances of conflicting with your application code flows are minuscule.



### Headers
It is possible to control the headers on the response of an `endpoint` by passing an object under the `headers` field:
```json
{
  "verb": "GET",
  "path": "/my_path_with_my_headers",
  "return_value": "{\"a\": 4}",
  "headers": {"Authorization": "foobar", "My-Custom": "stuff11"}
}
```
Headers can be anything you want, weather common recognized ones or custom ones.

### Response Times
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
  "max_response_millis": 500
}
```