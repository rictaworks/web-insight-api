# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Collect endpoint: visitor browsers authenticate via X-Site-Id + X-Api-Key only.
  # IMPORTANT: EventsController must call skip_before_action :authenticate_user! for this endpoint.
  allow do
    origins "*"

    resource "/api/v1/events/collect",
      headers: [ "Content-Type", "X-Site-Id", "X-Api-Key", "X-Timestamp" ],
      methods: [ :post, :options ]
  end

  # All other endpoints: restrict to the dashboard frontend only.
  # NOTE: collect endpoint is listed first so rack-cors uses it (detect/first-match)
  # and the wildcard resource never escalates methods for that path.
  allow do
    origins Rails.env.production? ? ENV.fetch("FRONTEND_URL") { raise "FRONTEND_URL must be set in production" } : ENV.fetch("FRONTEND_URL", "http://localhost:3000")

    resource "/api/v1/events/collect",
      headers: [ "Content-Type", "X-Site-Id", "X-Api-Key", "X-Timestamp" ],
      methods: [ :post, :options ]

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
