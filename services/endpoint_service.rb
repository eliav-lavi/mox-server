require 'json'

require_relative 'endpoint_id_composer'
require_relative '../models/endpoint'
require_relative '../models/client_error'
require_relative 'storage/internal_storage_client'

module Services
  class EndpointService
    CURRENT_ID_KEY = 'MOX_current_id'
    private_constant :CURRENT_ID_KEY
    
    def initialize(storage_client:, sinatra_app:, logger: Logger.new(STDOUT))
      @storage_client = storage_client
      @sinatra_app = sinatra_app
      @logger = logger

      current_id = storage_client.get(key: CURRENT_ID_KEY) || 0
      storage_client.set(key: CURRENT_ID_KEY, value: current_id)
    end

    def self.build(sinatra_app)
      storage_client = Services::Storage::InternalStorageClient.instance
      EndpointService.new(storage_client: storage_client, sinatra_app: sinatra_app)
    end

    def get_all_endpoints
      @storage_client
        .get_all(prefix: Services::EndpointIdComposer::PREFIX)
        .map { |raw_endpoint| Models::Endpoint.new(JSON.parse(raw_endpoint)) }
    end

    def remove_all_endpoints
      all_endpoints = get_all_endpoints
      all_endpoints.each { |endpoint| remove_endpoint(endpoint_id: endpoint.id) }
      all_endpoints
    end

    def add_endpoint(endpoint_request:, id: nil)
      next_id = id || @storage_client.incr(key: CURRENT_ID_KEY)
      endpoint = Models::Endpoint.build(endpoint_request, id: next_id)

      @storage_client.set(key: Services::EndpointIdComposer.call(id: endpoint.id), value: endpoint.attributes.to_json)
      
      sleep_time = calculate_sleep_time(endpoint: endpoint)
      @sinatra_app.register_endpoint(endpoint: endpoint, sleep_time: sleep_time)
      
      endpoint
    end

    def remove_endpoint(endpoint_id:)
      persisted_id = Services::EndpointIdComposer.call(id: endpoint_id)

      persisted_endpoint = @storage_client.get(key: persisted_id)
      raise EndpointIdNotFound if persisted_endpoint.nil?
      
      endpoint = Models::Endpoint.new(JSON.parse(persisted_endpoint))

      @storage_client.delete(key: persisted_id)
      @sinatra_app.deregister_endpoint(endpoint: endpoint)

      endpoint
    end

    def update_endpoint(endpoint_id:, endpoint_request:)
      remove_endpoint(endpoint_id: endpoint_id)
      add_endpoint(endpoint_request: endpoint_request, id: endpoint_id)
    end

    private def calculate_sleep_time(endpoint:)
      if endpoint.min_response_millis.nil? && endpoint.max_response_millis.nil?
        0
      elsif endpoint.max_response_millis.nil?
        endpoint.min_response_millis.to_f / 1000
      elsif endpoint.min_response_millis.nil?
        endpoint.max_response_millis.to_f / 1000
      elsif endpoint.min_response_millis > endpoint.max_response_millis
        @logger.warn("response time range is invalid for endpoint: #{endpoint.attributes}")
        0
      else
        rand((endpoint.min_response_millis.to_f / 1000)..(endpoint.max_response_millis.to_f / 1000))
      end
    end
  end
end
