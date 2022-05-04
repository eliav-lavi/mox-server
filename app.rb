require 'sinatra/base'
require 'sinatra/json'
require 'logger'
require 'json'
require 'dry-struct'

require_relative 'types'
require_relative 'models/endpoint'
require_relative 'models/endpoint_request'
require_relative 'models/client_error'
require_relative 'services/storage/internal_storage_client'
require_relative 'services/endpoint_id_composer'
require_relative 'services/endpoint_service'

class App < Sinatra::Base
  logger = Logger.new(STDOUT)
  logger.info("Starting mox-server ⚡")

  set :protection, false

  configure do
    enable :logging
    set :raise_errors, true
    set :dump_errors, true
    set :show_exceptions, true
  end

  before do
    content_type :json

    headers \
      'Access-Control-Allow-Methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Headers' => 'accept, authorization, origin'
  end

  options '*' do
    response.headers['Allow'] = 'HEAD,GET,PUT,DELETE,OPTIONS,POST'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept'
  end

  endpoint_service = Services::EndpointService.build(self)

  get '/healthcheck' do
    content_type :json
    { status: 'OK' }.to_json
  end

  get '/endpoint' do
    { response: endpoint_service.get_all_endpoints.map(&:attributes) }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to get all endpoints: #{e.message}" }.to_json
  end

  post '/endpoint' do
    endpoint_request = validate_request { Models::EndpointRequest.new(JSON.parse(request.body.read)) }

    endpoint = endpoint_service.add_endpoint(endpoint_request: endpoint_request)
    logger.info("created new endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue ClientError => e
    status 400
    log_error(e)
    { respone: "could not handle request to add endpoint: #{e.message}" }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to add endpoint: #{e.message}" }.to_json
  end

  post '/endpoints' do
    endpoint_requests = validate_request {
      raw_requests = JSON.parse(request.body.read)
      raw_requests.map do |raw_request|
        Models::EndpointRequest.new(raw_request)
      end
    }

    endpoints = endpoint_requests.map do |endpoint_request|
      endpoint_service.add_endpoint(endpoint_request: endpoint_request)
    end

    logger.info("created #{endpoints.count} new endpoints [#{endpoints.map(&:name).join(', ')}]")

    { response: endpoints.map(&:attributes) }.to_json
  rescue ClientError => e
    status 400
    log_error(e)
    { respone: "could not handle request to add endpoints: #{e.message}" }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to add endpoints: #{e.message}" }.to_json
  end

  put '/endpoint/:id' do
    endpoint_request = validate_request { Models::EndpointRequest.new(JSON.parse(request.body.read)) }

    endpoint_id = validate_endpoint_id(params)
    endpoint = endpoint_service.update_endpoint(endpoint_id: endpoint_id, endpoint_request: endpoint_request)

    logger.info("updated endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue ClientError => e
    status 400
    log_error(e)
    { respone: "could not handle request to update endpoint: #{e.message}" }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to update endpoint: #{e.message}" }.to_json
  end

  delete '/endpoint/:id' do
    endpoint_id = validate_endpoint_id(params)
    endpoint = endpoint_service.remove_endpoint(endpoint_id: endpoint_id)

    logger.info("removed endpoint: #{endpoint.verb} #{endpoint.path}")

    { response: endpoint.attributes }.to_json
  rescue ClientError => e
    status 400
    log_error(e)
    { respone: "could not handle request to remove endpoint: #{e.message}" }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to remove endpoint: #{e.message}" }.to_json
  end

  delete '/endpoints' do
    removed_endpoints = endpoint_service.remove_all_endpoints

    logger.info("successfuly removed #{removed_endpoints.count} endpoints")

    { response: "OK" }.to_json
  rescue StandardError => e
    status 500
    log_error(e)
    { respone: "could not handle request to remove endpoint: #{e.message}" }.to_json
  end

  not_found do
    status 492
    { respone: "MOX ERROR: endpoint doesn't exist" }.to_json
  end

  METHODS = {'GET' => :get, 'POST' => :post, 'PUT' => :put, 'PATCH' => :patch, 'DELETE' => :delete}
  RESERVED_STATUS_CODES = [491, 591, 492]

  def self.register_endpoint(endpoint:, sleep_time:)
    if RESERVED_STATUS_CODES.include?(endpoint.status_code)
      raise "status code #{endpoint.status_code} is reserved for Mox and cannot be used for user-defined endpoints"
    end
    method = METHODS[endpoint.verb]
    self.send(method, endpoint.path) do
      content_type :json
      body = JSON.parse(request.body.read) rescue nil
      sleep(sleep_time)

      status endpoint.status_code
      endpoint.headers.each { |k, v| headers[k] = v }
      body endpoint_return_value(endpoint_id: endpoint.id,
                                 params: params,
                                 body: body,
                                 storage_client: Services::Storage::InternalStorageClient.instance)
    rescue TemplateEvaluationError => e
      status 491
      log_error(e)
      { respone: "MOX ERROR: endpoint response could not be returned template evaluation error: #{e.message}" }.to_json
    rescue InvalidTemplateError => e
      status 491
      log_error(e)
      { respone: "MOX ERROR: endpoint response could not be returned due to bad syntax: #{e.message}" }.to_json
    rescue => e
      status 591
      log_error(e)
      { respone: "MOX ERROR: endpoint response could not be returned unexpectedly. #{e.message}" }.to_json
    end
  end

  # since the storage is the single source of truth, we fetch the current endpoint from it upon each serve
  private def endpoint_return_value(endpoint_id:, params:, body:, storage_client:)
    endpoint_id = Services::EndpointIdComposer.call(id: endpoint_id)
    persisted_endpoint = Models::Endpoint.new(JSON.parse(storage_client.get(key: endpoint_id)))
    persisted_endpoint.return_value_json(binding)
  end

  def self.deregister_endpoint(endpoint:)
    self.routes[endpoint.verb.upcase].delete_if do |m|
      m[0].safe_string == Mustermann.new(endpoint.path).safe_string
    end
  end


  private def validate_endpoint_id(params)
    validate_request {
      parsed_id = Integer(params['id'])
      raise EndpointIdNotFound unless parsed_id
      parsed_id
    }
  end

  private def validate_request(&block)
    begin
      block.call
    rescue StandardError => e
      raise InvalidRequest.new(e.message)
    end
  end

  private def log_error(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")
  end
end