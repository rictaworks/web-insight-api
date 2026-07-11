require 'base64'

module Api
  module V1
    module Admin
      class SitesController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        before_action :admin_authenticate!

        # GET /api/v1/admin/sites
        def index
          @sites = Site.order(created_at: :asc)
          render json: @sites, status: :ok
        end

        # POST /api/v1/admin/sites/:id/reset_ai
        def reset_ai
          @site = Site.find(params[:id])
          reset_daily_usage(@site)
          render json: { message: 'AI recommendation usage limit reset successfully' }, status: :ok
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Site not found' }, status: :not_found
        end

        private

        def reset_daily_usage(site)
          usage_date = 3.hours.ago.to_date
          usage = site.daily_ai_usages.find_or_initialize_by(usage_date: usage_date)
          usage.update!(used_count: 0, reset_at: Time.current)
        end

        # ADMIN_USERNAME/ADMIN_PASSWORD are required in production (see
        # config/initializers/require_admin_credentials.rb, which raises at
        # boot if either is unset there), so the 'admin'/'password' fallback
        # below only ever applies in development/test.
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
