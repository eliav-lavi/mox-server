require 'singleton'

module Services
  module Storage
    class InternalStorageClient
      include ::Singleton

      def initialize
        @data = {}
      end
  
      def set(key:, value:)
        @data[key] = value
      end
  
      def get(key:)
        @data[key]
      end
  
      def get_all(prefix: nil)
        keys = @data.keys.filter { |key| key.to_s.start_with?(prefix) }
        @data.values_at(*keys).compact
      end
  
      def delete(key:)
        @data.delete(key)
      end
  
      def incr(key:)
        @data[key] = @data[key] + 1
      end
    end
  end
end