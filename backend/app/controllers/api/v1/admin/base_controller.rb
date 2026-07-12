require 'base64'

module Api
  module V1
    module Admin
      class BaseController < ApplicationController
        BODY_BEARING_METHODS = %w[POST PUT PATCH DELETE].freeze

        skip_before_action :authenticate_user!, raise: false
        before_action :admin_authenticate!
        before_action :require_json_content_type!, if: :body_bearing_request?

        private

        # A plain HTML <form> can only submit application/x-www-form-urlencoded
        # or multipart/form-data — never application/json — so this blocks the
        # CSRF path where a third-party page auto-submits a form (with a
        # hidden _method field) against this Basic-Auth-only, CSRF-token-free
        # API using the admin's browser-cached credentials. Rack::MethodOverride
        # must stay global for RailsAdmin (see config/application.rb), so this
        # is the layer that actually stops it from reaching these actions.
        def body_bearing_request?
          BODY_BEARING_METHODS.include?(request.request_method)
        end

        def require_json_content_type!
          return if request.media_type == 'application/json'

          render json: { error: 'Content-Type must be application/json' }, status: :unsupported_media_type
        end

        def admin_authenticate!
          return if authorized?

          headers['WWW-Authenticate'] = 'Basic realm="Admin Area"'
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end

        def authorized?
          auth_header = request.headers['Authorization']
          return false unless auth_header.present? && auth_header.start_with?('Basic ')

          username, password = decode_basic_credentials(auth_header)
          valid_credentials?(username, password)
        rescue StandardError => e
          logger.warn "Basic Auth parse error: #{e.message}"
          false
        end

        def decode_basic_credentials(auth_header)
          encoded_credentials = auth_header.split(' ', 2).last
          Base64.decode64(encoded_credentials).split(':', 2)
        end

        def valid_credentials?(username, password)
          expected_username = ENV.fetch('ADMIN_USERNAME', 'admin')
          expected_password = ENV.fetch('ADMIN_PASSWORD', 'password')

          ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username) &&
            ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)
        end
      end
    end
  end
end
