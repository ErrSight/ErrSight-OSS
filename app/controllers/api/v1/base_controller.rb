module Api
  module V1
    class BaseController < ActionController::API
      TOKEN_FORMAT = /\A(elp|elr)_[0-9a-f]{48}\z/

      before_action :authenticate_api_key!

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActionController::ParameterMissing, with: :bad_request

      class_attribute :required_scope, instance_accessor: false
      self.required_scope = :write

      private

      def authenticate_api_key!
        token = extract_token

        unless token.to_s.match?(TOKEN_FORMAT)
          return render json: { error: "Invalid or missing API key" }, status: :unauthorized
        end

        @api_key = ApiKey.find_active_by_token(token)
        @project = @api_key&.project

        unless @project
          return render json: { error: "Invalid or missing API key" }, status: :unauthorized
        end

        if @project.organization&.discarded?
          return render json: { error: "Organization is no longer active" }, status: :forbidden
        end

        unless scope_allowed?(@api_key.scope)
          return render json: { error: "API key lacks required scope: #{self.class.required_scope}" }, status: :forbidden
        end

        @api_key.touch_last_used!
      end

      def extract_token
        request.headers["X-API-Key"].presence ||
          request.headers["Authorization"]&.sub(/\ABearer\s+/, "")
      end

      def scope_allowed?(scope)
        case self.class.required_scope
        when :write then scope == "write"
        # A leaked write key should let an attacker spam ingestion, not read
        # stored customer data. Read endpoints require an explicit read key.
        when :read  then scope == "read"
        else false
        end
      end

      # Never echo the raw exception message to API clients. Rails'
      # RecordNotFound message names the model and queried id, which leaks
      # internal schema and enables cross-tenant id enumeration.
      def not_found(_exception)
        render json: { error: "Not found", code: "NOT_FOUND" }, status: :not_found
      end

      def bad_request(_exception)
        render json: { error: "Bad request", code: "BAD_REQUEST" }, status: :bad_request
      end
    end
  end
end
