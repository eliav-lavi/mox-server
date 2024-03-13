require 'dry-struct'
require 'json'
require 'erb'
require 'base64'

require_relative '../types'
require_relative 'endpoint_request'
require_relative 'client_error'

module Models
  class Endpoint < Dry::Struct
    transform_keys(&:to_sym)

    attribute :id, Types::Integer
    attribute :verb, Types::String
    attribute :path, Types::String
    attribute :return_value, Types::Any
    attribute :return_value_binary, Types::Bool.default(false)
    attribute :min_response_millis?, Types::Integer
    attribute :max_response_millis?, Types::Integer
    attribute :status_code, Types::Integer.default(200)
    attribute :headers, Types::Hash.map(Types::String, Types::String).default({})

    def return_value_json(binding)
      template = ERB.new(return_value)
      implemented_template = template.result(binding)
      JSON.parse(implemented_template).to_json
    rescue SyntaxError => e
      raise InvalidTemplateError.new(e.message)
    rescue StandardError => e
      raise TemplateEvaluationError.new(e.message)
    end

    def return_value_binary
      Base64.decode64(return_value)
    rescue StandardError => e
      raise InvalidBinaryError.new(e.message)
    end

    def name
      "#{verb} #{path}"
    end

    def return_value_binary?
      self[:return_value_binary]
    end

    def self.build(obj, id: nil)
      effective_id = id || obj['id']
      Endpoint.new(id: effective_id, **obj.attributes)
    end
  end
end
