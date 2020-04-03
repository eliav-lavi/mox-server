require 'redis'

module Services
  class WrappedRedisClient
    def self.build(host:, port:)
      redis_client = Redis.new(host: host, port: port)
      Services::WrappedRedisClient.new(client: redis_client)
    end

    def initialize(client:)
      @client = client
    end

    def set(key:, value:)
      @client.set(key, value)
    end

    def get(key:)
      @client.get(key)
    end

    def get_all(prefix: nil)
      all_keys = @client.keys("#{prefix}*")
      return [] if all_keys.empty?
      @client.mget(all_keys)
    end

    def delete(key:)
      @client.del(key)
    end

    def incr(key:)
      @client.incr(key)
    end
  end
end