if Rails.env.production? && (ENV['ADMIN_USERNAME'].blank? || ENV['ADMIN_PASSWORD'].blank?)
  raise 'ADMIN_USERNAME and ADMIN_PASSWORD environment variables must be set in production'
end
