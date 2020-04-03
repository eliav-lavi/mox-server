module Services
  module EndpointIdComposer
    PREFIX = "MOX_ENDPOINT"
    class << self
      def call(id:)
        "#{PREFIX}::#{id}"
      end
    end
  end
end