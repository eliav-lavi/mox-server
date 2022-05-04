require 'rspec'
require 'rack/test'
require 'json'

require_relative '../app.rb'

RSpec.describe 'mox' do
  include Rack::Test::Methods

  def app
    ::App
  end

  before(:each) do
    delete('/endpoints')
  end

  BASE_ENDPOINT = <<-JSON.freeze
    {
      "verb": "GET",
      "path": "/foo",
      "return_value": "{\\"a\\": 4}"
    }
  JSON

  BASE_HEADERS = { 'CONTENT_TYPE' => 'application/json' }

  describe 'endpoint lifecycle' do
    it 'allows adding endpoints dynamically' do
      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(0)

      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(1)
      
      get('/foo')
      expect(last_response_parsed_body).to eq({"a" => 4})
      expect(last_response.status).to eq(200)
    end

    it 'allows setting custom status codes for endpoint' do
      endpoint = build_endpoint_request(status_code: 219).to_json
      post('/endpoint', endpoint, BASE_HEADERS)

      get('/foo')
      expect(last_response.status).to eq(219)
    end

    it 'allows setting custom headers for endpoint' do
      endpoint = build_endpoint_request(headers: {"My-Header" => "my value"}).to_json
      post('/endpoint', endpoint, BASE_HEADERS)

      get('/foo')
      expect(last_response.headers["My-Header"]).to eq("my value")
    end

    it 'allows de-registering endpoints' do
      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(0)

      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      endpoint_id = last_response_parsed_body["response"]["id"]
      
      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(1)

      get('/foo')
      expect(last_response.status).to eq(200)
      
      delete("/endpoint/#{endpoint_id}")
      expect(last_response.status).to eq(200)

      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(0)

      get('/foo')
      expect(last_response).not_to be_ok
    end

    it 'allows updating an existing endpoint' do
      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      endpoint_id = last_response_parsed_body["response"]["id"]

      get('/foo')
      expect(last_response_parsed_body).to eq({"a" => 4})

      updated_endpoint = build_endpoint_request(return_value: "{\"b\": true}").to_json
      put("/endpoint/#{endpoint_id}", updated_endpoint)
      expect(last_response.status).to eq(200)

      get('/foo')
      expect(last_response_parsed_body).to eq({"b" => true})  
    end

    it 'allows adding endpoints in batch' do
      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(0)

      endpoints = [build_endpoint_request, build_endpoint_request(verb: 'POST')].to_json
      post('/endpoints', endpoints, BASE_HEADERS)

      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(2)
    end

    it 'allows deleting endpoints in batch' do
      endpoints = [build_endpoint_request, build_endpoint_request(verb: 'POST')].to_json
      post('/endpoints', endpoints, BASE_HEADERS)

      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(2)

      delete('/endpoints')
      
      get('/endpoint')
      expect(last_response_parsed_body["response"].count).to eq(0)
    end
  end

  describe 'create/update/delete validations' do
    mandatory_fields = ["verb", "path", "return_value"]
    mandatory_fields.each do |mandatory_field|
      it "returns status code 400 if request is missing #{mandatory_field}" do
        invalid_request = build_endpoint_request.tap { |r| r.delete(mandatory_field) }
        post('/endpoint', invalid_request.to_json, BASE_HEADERS)
        expect(last_response.status).to eq(400)
      end
    end

    it 'returns status code 400 if request has invalid JSON syntax' do 
      invalid_request = '{"a: 3}' # invalid since key `a` was not declared as a proper string
      post('/endpoint', invalid_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(400)
    end

    it 'returns status code 400 if delete was called on a nonexisting endpoint id' do
      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/endpoint')
      max_id = last_response_parsed_body["response"].map { |m| m["id"] }.max
      nonexistent_id = max_id + 1
      
      delete("/endpoint/#{nonexistent_id}")
      expect(last_response.status).to eq(400)
    end

    it 'returns status code 400 if update was called on a nonexisting endpoint id' do
      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/endpoint')
      max_id = last_response_parsed_body["response"].map { |m| m["id"] }.max
      nonexistent_id = max_id + 1
      
      put("/endpoint/#{nonexistent_id}", build_endpoint_request.to_json)
      expect(last_response.status).to eq(400)
    end

    it 'returns status code 400 if delete was called on a non-numeric id' do
      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      nonexistent_id = "string_id:11"
      delete("/endpoint/#{nonexistent_id}")
      expect(last_response.status).to eq(400)
    end

    it 'returns status code 400 if update was called on a non-numeric id' do
      post('/endpoint', build_endpoint_request.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      nonexistent_id = "string_id:11"
      put("/endpoint/#{nonexistent_id}", build_endpoint_request.to_json)
      expect(last_response.status).to eq(400)
    end
  end

  describe 'dynamic templates' do
    it 'exposes query params as values in return_value through ERB' do
      return_value = "{\"bar\": \"<%= params['bar'].upcase %>\"}"
      endpoint = build_endpoint_request(return_value: return_value)
      post('/endpoint', endpoint.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/foo?bar=quu')
      expect(last_response_parsed_body).to eq({"bar" => "QUU"})
      expect(last_response.status).to eq(200)
    end

    it 'exposes body in return_value through ERB' do
      return_value = "{\"bar\": \"<%= body['bar']['nested'].upcase %>\"}"
      endpoint = build_endpoint_request(verb: 'POST', return_value: return_value)
      post('/endpoint', endpoint.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      body = '{"bar": {"nested": "quu"}}'
      post('/foo', body, BASE_HEADERS)
      expect(last_response_parsed_body).to eq({"bar" => "QUU"})
      expect(last_response.status).to eq(200)
    end

    it 'returns status code 491 when an error occurs in evaluating dynamic template' do
      return_value = "{\"bar\": \"<%= params['bar'].some_nonexisting_method %>\"}"
      endpoint = build_endpoint_request(return_value: return_value)
      post('/endpoint', endpoint.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/foo?bar=quu')
      expect(last_response.status).to eq(491)
    end

    it 'returns status code 491 when an error occurs in evaluating dynamic template' do
      return_value = "{\"bar\": \"<%= params['bar'].some_nonexisting_method %>\"}"
      endpoint = build_endpoint_request(return_value: return_value)
      post('/endpoint', endpoint.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/foo?bar=quu')
      expect(last_response.status).to eq(491)
    end

    it 'returns status code 491 when an dynamic template syntax is invalid' do
      return_value = "{\"bar\": \"<%= params['bar'] |> upcase %>\"}" # invalid syntax - this is not valid Ruby in there!
      endpoint = build_endpoint_request(return_value: return_value)
      post('/endpoint', endpoint.to_json, BASE_HEADERS)
      expect(last_response.status).to eq(200)

      get('/foo?bar=quu')
      expect(last_response.status).to eq(491)
    end
  end


  private def last_response_parsed_body
    JSON.parse(last_response.body)
  end

  private def build_endpoint_request(verb: nil, return_value: nil, status_code: nil, headers: nil)
    JSON.parse(BASE_ENDPOINT)
      .tap { |json| verb && json["verb"] = verb }
      .tap { |json| return_value && json["return_value"] = return_value }
      .tap { |json| status_code && json["status_code"] = status_code }
      .tap { |json| headers && json["headers"] = headers }
  end
end