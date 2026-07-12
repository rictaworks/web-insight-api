require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Tokyo"


    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Required middlewares for Rails Admin HTML interface
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: '_web_insight_api_session'
    config.middleware.use ActionDispatch::Flash

    # Rate limiting must run before signature verification so that requests
    # with invalid/missing credentials are still throttled instead of always
    # short-circuiting with 401 before Rack::Attack sees them.
    config.middleware.use Rack::Attack

    # Rack::MethodOverride must run after Rack::Attack (see the comment on
    # that throttle for why) and must stay in this GLOBAL stack — RailsAdmin
    # itself raises at boot if it's missing here (RailsAdmin::Engine's
    # after_initialize check inspects Rails.application.config.middleware
    # specifically, not an engine-scoped stack, so it cannot be scoped to
    # RailsAdmin::Engine alone). A global Rack::MethodOverride would let a
    # plain (non-preflighted) HTML form POST rewrite itself into a PUT/PATCH/
    # DELETE against a JSON admin API — e.g. PUT /api/v1/admin/bot_rules,
    # which has no CSRF token since ApplicationController < ActionController::API
    # — and execute using the admin's browser-cached Basic Auth credentials.
    # That's a real CSRF path: a genuine PUT via fetch() would need a CORS
    # preflight this app's origin allowlist would reject, but a "simple" POST
    # form never triggers a preflight at all. Api::V1::Admin::BaseController
    # closes this by requiring Content-Type: application/json on every
    # state-changing admin request — a plain HTML form can only submit
    # application/x-www-form-urlencoded or multipart/form-data, never JSON.
    config.middleware.use Rack::MethodOverride

    # Register API key signature verification middleware
    require_relative "../app/middleware/api_signature_verification"
    config.middleware.use ApiSignatureVerification
  end
end
