module Api
  class BaseController < ActionController::API
    include ActionController::RateLimiting

    # rate_limit captures its store when the class loads; this resolves
    # Rails.cache per call instead, so tests can swap in a real store.
    class LazyCacheStore
      def method_missing(name, *args, **kwargs, &block) = Rails.cache.public_send(name, *args, **kwargs, &block)
      def respond_to_missing?(name, include_private = false) = Rails.cache.respond_to?(name, include_private)
    end
    RATE_LIMIT_STORE = LazyCacheStore.new

    rescue_from Registry::PublishVersion::PublishError do |e|
      render json: { error: e.message }, status: e.status
    end

    private

    # Every authenticated endpoint names the kind of token it accepts. A
    # publish token cannot post a comment and a client token cannot publish,
    # and neither can be mistaken for the other by forgetting to look.
    def authenticate_api_token!(kind:)
      raw = request.authorization.to_s[/\ABearer (.+)\z/, 1]
      token = ApiToken.authenticate(raw)

      if token.nil?
        return render json: { error: "invalid or expired token" }, status: :unauthorized
      end
      unless token.kind == kind.to_s
        return render json: { error: "this token is not a #{kind} token" }, status: :forbidden
      end
      # Suspension kills live credentials, not just future sign-ins — the same
      # rule the cookie session follows. Said as forbidden rather than
      # unauthorized: the token is fine, the account is not, and telling a
      # suspended publisher their token expired sends them to mint another.
      if token.user.suspended_at.present?
        return render json: { error: "account is suspended" }, status: :forbidden
      end

      @current_token = token
      # Domain code reads Current.user — comment authorship, the publisher
      # badge, audit attribution. Setting it here means an API request and a
      # browser request are the same request as far as the models are
      # concerned. CurrentAttributes resets between requests.
      Current.api_user = token.user
    end

    def authenticate_publish_token! = authenticate_api_token!(kind: :publish)
    def authenticate_client_token! = authenticate_api_token!(kind: :client)

    attr_reader :current_token
    def current_user = @current_token&.user
  end
end
