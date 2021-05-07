require_relative '../types'
require 'dry-struct'
require 'json'
require 'erb'

module Models
  class Endpoint < Dry::Struct
    transform_keys(&:to_sym)

    attribute :id, Types::Integer
    attribute :verb, Types::String
    attribute :path, Types::String
    attribute :return_value, Types::Any
    attribute :min_response_millis?, Types::Integer
    attribute :max_response_millis?, Types::Integer

    def return_value_json(binding)
      template = ERB.new(return_value)
      implemented_template = template.result(binding)
      JSON.parse(implemented_template).to_json
    end

    def self.build(obj, id: nil)
      effective_id = id || obj['id']
      Endpoint.new(id: effective_id, **obj.transform_keys(&:to_sym))
    end
  end
end
