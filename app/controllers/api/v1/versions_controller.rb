module Api
  module V1
    # POST /api/v1/plugins/:publisher/:plugin/versions
    # Authorization: Bearer omp_…   Body: the .tar.gz, nothing else.
    # All metadata derives from the manifest inside the tarball.
    class VersionsController < BaseController
      # Attempt-level throttle: invalid archives burn decompression work
      # without ever creating rows for the submission quotas to count
      rate_limit to: 30, within: 15.minutes, only: :create, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

      before_action :authenticate_publish_token!

      MAX_BODY_BYTES = Registry::TarballInspector::MAX_TARBALL_BYTES

      def create
        # Cap before buffering: declared length is checked, and the read itself
        # is bounded so a lying Content-Length can't balloon memory either.
        if request.content_length.to_i > MAX_BODY_BYTES
          return render json: { error: "tarball exceeds #{MAX_BODY_BYTES / 1.megabyte}MB limit" }, status: :content_too_large
        end
        body = request.body.read(MAX_BODY_BYTES + 1) || ""
        if body.bytesize > MAX_BODY_BYTES
          return render json: { error: "tarball exceeds #{MAX_BODY_BYTES / 1.megabyte}MB limit" }, status: :content_too_large
        end

        publisher = Publisher.find_by!(name: params[:publisher])
        version = Registry::PublishVersion.new(
          user: current_token.user,
          publisher: publisher,
          plugin_name: params[:plugin],
          tarball_bytes: body,
          token: current_token
        ).call

        render json: {
          plugin: version.plugin.full_name,
          version: version.version,
          sha256: version.sha256,
          state: version.state,
          message: "Accepted — running the review pipeline. Clean versions go live after a short hold (~15 min).",
          url: "#{DataPlane.base_url}/plugins/#{version.plugin.publisher.name}/#{version.plugin.name}"
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "unknown publisher #{params[:publisher]}" }, status: :not_found
      end
    end
  end
end
