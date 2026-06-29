if Rails.env.production? && ENV['JWT_SECRET'].blank?
  raise 'JWT_SECRET environment variable must be set in production'
end
