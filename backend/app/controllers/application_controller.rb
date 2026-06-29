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
    token = request.headers['Authorization']&.split&.last
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
    raw = ENV['JWT_SECRET']
    if raw.present?
      raw
    elsif Rails.env.production?
      raise 'JWT_SECRET environment variable must be set in production'
    else
      Rails.application.credentials.secret_key_base
    end
  end

  def find_user_by_sub(sub)
    return nil unless ActiveRecord::Base.connection.table_exists?(:users)

    User.find_by(google_sub: sub)
  end

  def mock_development_user
    # DBマイグレーションが実行されるまではモックユーザーを返さない（エラー防止）
    return nil unless ActiveRecord::Base.connection.table_exists?(:users)

    sub = ENV.fetch('DEV_GOOGLE_SUB', 'dev_test_sub')
    name = ENV.fetch('DEV_DISPLAY_NAME', 'Dev Test User')

    User.find_or_create_by!(google_sub: sub) do |user|
      user.display_name = name
    end
  end
end
