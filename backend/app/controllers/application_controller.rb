class ApplicationController < ActionController::API
  before_action :authenticate_user!

  def current_user
    @current_user ||= authenticate_by_token
  end

  def authenticate_user!
    render json: { error: 'Unauthorized' }, status: :unauthorized unless current_user
  end

  private

  def authenticate_by_token
    return mock_development_user if dev_auto_login?

    decode_token_and_find_user
  end

  def dev_auto_login?
    Rails.env.development? && ENV['DEV_AUTO_LOGIN'] == 'true'
  end

  def decode_token_and_find_user
    token = request.headers['Authorization']&.split(' ', 2)&.last
    return nil unless token

    payload = decode_jwt_token(token)
    return nil unless payload

    find_user_by_sub(payload['sub'])
  end

  def decode_jwt_token(token)
    decoded = JWT.decode(token, jwt_signing_secret, true, {
                           algorithm: 'HS256',
                           required_claims: %w[exp sub]
                         })
    decoded.first
  rescue JWT::DecodeError, ArgumentError => e
    Rails.logger.warn "JWT Decode Error: #{e.class}: #{e.message}"
    nil
  end

  def jwt_signing_secret
    raw = ENV.fetch('JWT_SECRET', nil)
    if raw.blank?
      raise 'JWT_SECRET is not configured' if Rails.env.production?

      Rails.logger.warn 'JWT_SECRET not set; JWT authentication unavailable'
      return nil
    end
    raw
  end

  def find_user_by_sub(sub)
    unless ActiveRecord::Base.connection.table_exists?(:users)
      Rails.logger.warn 'users table not found, skipping auth lookup'
      return nil
    end

    User.find_by(google_sub: sub)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def mock_development_user
    unless ActiveRecord::Base.connection.table_exists?(:users)
      Rails.logger.warn 'users table not found, cannot create dev mock user'
      return nil
    end

    sub = ENV.fetch('DEV_GOOGLE_SUB', 'dev_test_sub')
    name = ENV.fetch('DEV_DISPLAY_NAME', 'Dev Test User')

    user = begin
      User.find_or_create_by(google_sub: sub) do |u|
        u.display_name = name
      end
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.warn 'Concurrent dev user creation race; retrying find'
      User.find_by(google_sub: sub)
    end

    if user && !user.persisted?
      Rails.logger.warn "Concurrent dev user creation race (validation): #{user.errors.full_messages.join(', ')}"
      user = User.find_by(google_sub: sub)
    end

    return nil unless user

    user.update(display_name: name) if user.display_name != name
    user
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
