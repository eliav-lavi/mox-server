require 'sinatra/base'
require 'sinatra/json'
require 'logger'
require 'json'
require 'dry-struct'

require_relative 'types'
require_relative 'models/endpoint'
require_relative 'services/wrapped_redis_client'
require_relative 'services/endpoint_id_composer'

class App < Sinatra::Base

  set :protection, false

  logger = Logger.new(STDOUT)

  configure :production, :development do
    enable :logging, :dump_errors, :raise_errors
    set :show_exceptions, :after_handler
  end

  redis_client = Services::WrappedRedisClient.build(host: ENV["REDIS_HOST"], port: ENV["REDIS_PORT"])
  CURRENT_ID_KEY = 'MOX_current_id'
  current_id = redis_client.get(key: CURRENT_ID_KEY) || 0
  redis_client.set(key: CURRENT_ID_KEY, value: current_id)
  
  before do
    content_type :json

    headers \
      'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Headers' => 'accept, authorization, origin'
  end

  options '*' do
    response.headers['Allow'] = 'HEAD,GET,PUT,DELETE,OPTIONS,POST'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept'
  end

  get '/healthcheck' do
    content_type :json
    { status: 'OK' }.to_json
  end

  get '/endpoint' do
    { response: get_all_endpoints(redis_client: redis_client).map(&:attributes) }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to get all endpoints: #{e.message}" }.to_json
  end

  post '/endpoint' do
    content_type :json

    next_id = redis_client.incr(key: CURRENT_ID_KEY)
    endpoint = Models::Endpoint.build(JSON.parse(request.body.read), id: next_id)

    redis_client.set(key: Services::EndpointIdComposer.call(id: endpoint.id), value: endpoint.attributes.to_json)
    
    add_endpoint(endpoint: endpoint, redis_client: redis_client)
    
    logger.info("created new endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to add endpoint: #{e.message}" }.to_json
  end

  post '/endpoints' do
    content_type :json

    raw_endpoints = JSON.parse(request.body.read)
    
    endpoints = raw_endpoints.map do |raw_endpoint|
      next_id = redis_client.incr(key: CURRENT_ID_KEY)
      endpoint = Models::Endpoint.build(raw_endpoint, id: next_id)

      redis_client.set(key: Services::EndpointIdComposer.call(id: endpoint.id), value: endpoint.attributes.to_json)
      
      add_endpoint(endpoint: endpoint, redis_client: redis_client)
      
      logger.info("created new endpoint: #{endpoint.verb} #{endpoint.path}")

      endpoint
    end

    { response: endpoints.map(&:attributes) }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to add endpoints: #{e.message}" }.to_json
  end

  put '/endpoint' do
    content_type :json

    endpoint = Models::Endpoint.build(JSON.parse(request.body.read))

    redis_client.delete(key: Services::EndpointIdComposer.call(id: endpoint.id))
    remove_endpoint(endpoint: endpoint)

    redis_client.set(key: Services::EndpointIdComposer.call(id: endpoint.id), value: endpoint.attributes.to_json)
    add_endpoint(endpoint: endpoint, redis_client: redis_client)

    logger.info("updated endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to update endpoint: #{e.message}" }.to_json
  end

  delete '/endpoint' do
    content_type :json

    endpoint_id = Services::EndpointIdComposer.call(id: params['id'])

    persisted_endpoint = redis_client.get(key: endpoint_id)
    raise "endpoint ##{endpoint_id} not found" if persisted_endpoint.nil?
    
    endpoint = Models::Endpoint.new(JSON.parse(persisted_endpoint))

    logger.info("found endpoint to remove: #{endpoint}")

    redis_client.delete(key: endpoint_id)

    remove_endpoint(endpoint: endpoint)

    logger.info("removed endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to remove endpoint: #{e.message}" }.to_json
  end

  delete '/endpoints' do
    content_type :json
    all_endpoints = get_all_endpoints(redis_client: redis_client)
    all_endpoints.map do |endpoint|
      endpoint_id = Services::EndpointIdComposer.call(id: endpoint.id)
      redis_client.delete(key: endpoint_id)
      remove_endpoint(endpoint: endpoint)
      logger.info("removed endpoint: #{endpoint.verb} #{endpoint.path}")
    end
    
    logger.info("successfuly removed #{all_endpoints.count} endpoints")

    { response: "OK" }.to_json
  rescue StandardError => e
    status 400
    { respone: "could not handle request to remove endpoint: #{e.message}" }.to_json
  end

  private def get_all_endpoints(redis_client:)
    redis_client
      .get_all(prefix: Services::EndpointIdComposer::PREFIX)
      .map { |raw_endpoint| Models::Endpoint.new(JSON.parse(raw_endpoint)) }
  end
  
  METHODS = {'GET' => :get, 'POST' => :post, 'PUT' => :put, 'PATCH' => :patch, 'DELETE' => :delete}
  RESERVED_STATUS_CODES = [492, 592]
  private def add_endpoint(endpoint:, redis_client:)
    if RESERVED_STATUS_CODES.include?(endpoint.status_code)
      raise "status code #{endpoint.status_code} is reserved for Mox and cannot be used for user-defined endpoints"
    end
    method = METHODS[endpoint.verb]
    self.class.send(method, endpoint.path) do
      content_type :json
      body = JSON.parse(request.body.read) rescue nil
      sleep(calculate_sleep_time(endpoint: endpoint))

      status endpoint.status_code
      endpoint.headers.each { |k, v| headers[k] = v }
      body endpoint_return_value(endpoint: endpoint, params: params, body: body, redis_client: redis_client)
    rescue SyntaxError => e
      status 592
      { respone: "MOX ERROR: endpoint response could not be returned due to bad syntax: #{e.message}" }.to_json
    end
  end

  not_found do
    status 492
    { respone: "MOX ERROR: endpoint doesn't exist" }.to_json
  end

  private def endpoint_return_value(endpoint:, params:, body:, redis_client:)
    endpoint_id = Services::EndpointIdComposer.call(id: endpoint.id)
    persisted_endpoint = Models::Endpoint.new(JSON.parse(redis_client.get(key: endpoint_id)))
    persisted_endpoint.return_value_json(binding)
  end

  private def calculate_sleep_time(endpoint:)
    if endpoint.min_response_millis.nil? && endpoint.max_response_millis.nil?
      0
    elsif endpoint.max_response_millis.nil?
      endpoint.min_response_millis.to_f / 1000
    elsif endpoint.min_response_millis.nil?
      endpoint.max_response_millis.to_f / 1000
    elsif endpoint.min_response_millis > endpoint.max_response_millis
      logger.warn("response time range is invalid for endpoint: #{endpoint.attributes}")
      0
    else
      rand((endpoint.min_response_millis.to_f / 1000)..(endpoint.max_response_millis.to_f / 1000))
    end
  end

  private def remove_endpoint(endpoint:)
    self.class.routes[endpoint.verb.upcase].delete_if do |m|
      m[0].safe_string == Mustermann.new(endpoint.path).safe_string
    end
  end
end