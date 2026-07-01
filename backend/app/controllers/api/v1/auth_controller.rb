module Api
  module V1
    # rubocop:disable Metrics/ClassLength
    class AuthController < ApplicationController
      skip_before_action :authenticate_user!, only: [:google]

      def google
        if dev_auto_login?
          handle_dev_auto_login
          return
        end

        auth_code = params[:auth_code]
        if auth_code.blank?
          render json: { error: 'auth_code is required' }, status: :bad_request
          return
        end

        process_google_auth(auth_code)
      end

      def self.google_id_token_validator
        @google_id_token_validator ||= GoogleIDToken::Validator.new
      end

      private

      # rubocop:disable Metrics/MethodLength
      def process_google_auth(auth_code)
        id_token = id_token_shaped?(auth_code) ? auth_code : exchange_auth_code(auth_code)
        if id_token.blank?
          render json: { error: 'Invalid auth_code or failed to exchange tokens' }, status: :unauthorized
          return
        end

        payload = verify_id_token(id_token)
        if payload.blank? || payload['sub'].blank?
          render json: { error: 'Invalid Google ID token payload' }, status: :unauthorized
          return
        end

        user = upsert_user_from_payload(payload)
        render_auth_success(user)
      end
      # rubocop:enable Metrics/MethodLength

      def id_token_shaped?(value)
        value.count('.') == 2
      end

      def handle_dev_auto_login
        user = mock_development_user
        if user
          render_auth_success(user)
        else
          render json: { error: 'Failed to create mock user' }, status: :internal_server_error
        end
      end

      # rubocop:disable Metrics/MethodLength
      def upsert_user_from_payload(payload)
        google_sub = payload['sub']
        display_name = payload['name'] || 'Google User'

        user = begin
          User.find_or_create_by!(google_sub: google_sub) do |u|
            u.display_name = display_name
          end
        rescue ActiveRecord::RecordNotUnique
          User.find_by(google_sub: google_sub)
        end

        user.update(display_name: display_name) if user.display_name != display_name
        user
      end
      # rubocop:enable Metrics/MethodLength

      def render_auth_success(user)
        token = encode_jwt_token(user.google_sub)
        if token.blank?
          render json: { error: 'JWT_SECRET is not configured' }, status: :internal_server_error
          return
        end

        render json: { token: token, user: { id: user.id, display_name: user.display_name } }, status: :ok
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def exchange_auth_code(auth_code)
        uri = URI('https://oauth2.googleapis.com/token')
        client_id = ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil)
        client_secret = ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil)

        if client_id.blank? || client_secret.blank?
          Rails.logger.error 'Google OAuth client credentials are not configured'
          return nil
        end

        res = Net::HTTP.post_form(uri, exchange_params(auth_code, client_id, client_secret))
        unless res.is_a?(Net::HTTPSuccess)
          Rails.logger.error "Google Token Exchange failed: #{res.code} - #{res.body}"
          return nil
        end

        JSON.parse(res.body)['id_token']
      rescue StandardError => e
        Rails.logger.error "Google OAuth token exchange error: #{e.class}: #{e.message}"
        nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def exchange_params(auth_code, client_id, client_secret)
        {
          code: auth_code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: params[:redirect_uri] || 'postmessage',
          grant_type: 'authorization_code'
        }
      end

      def verify_id_token(id_token)
        client_id = ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil)
        if client_id.blank?
          Rails.logger.error 'GOOGLE_OAUTH_CLIENT_ID is not configured'
          return nil
        end

        self.class.google_id_token_validator.check(id_token, client_id)
      rescue StandardError => e
        Rails.logger.warn "Google ID Token validation failed: #{e.class}: #{e.message}"
        nil
      end

      def encode_jwt_token(google_sub)
        secret = jwt_signing_secret
        return nil if secret.blank?

        payload = {
          sub: google_sub,
          exp: 24.hours.from_now.to_i
        }
        JWT.encode(payload, secret, 'HS256')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
