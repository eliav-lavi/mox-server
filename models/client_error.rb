class ClientError < StandardError; end
class InvalidRequest < ClientError; end
class EndpointIdNotFound < ClientError; end
class InvalidTemplateError < ClientError; end
class TemplateEvaluationError < ClientError; end