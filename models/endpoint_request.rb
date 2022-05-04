require_relative '../types'
require 'dry-struct'
require 'json'
require 'erb'


module Models
  class EndpointRequest < Dry::Struct
    transform_keys(&:to_sym)

    attribute :verb, Types::String
    attribute :path, Types::String
    attribute :return_value, Types::Any
    attribute :min_response_millis?, Types::Integer
    attribute :max_response_millis?, Types::Integer
    attribute :status_code, Types::Integer.default(200)
    attribute :headers, Types::Hash.map(Types::String, Types::String).default({})
  end
end
