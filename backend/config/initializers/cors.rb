# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Collector endpoint: allow any registered customer site origin.
  # Authentication is enforced via X-Site-Id + X-Api-Key headers.
  allow do
    origins "*"

    resource "/api/v1/events/collect",
      headers: [ "Content-Type", "X-Site-Id", "X-Api-Key" ],
      methods: [ :post, :options ]
  end

  # All other endpoints: restrict to the dashboard frontend only.
  allow do
    origins ENV.fetch("FRONTEND_URL") { "http://localhost:3000" }

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
