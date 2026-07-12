RailsAdmin.config do |config|
  config.asset_source = :sprockets

  # Forces the Japanese locale for the admin interface, scoped to each
  # request only — see app/controllers/rails_admin_base_controller.rb for
  # why a bare `I18n.locale = :ja` here would leak across requests.
  config.parent_controller = '::RailsAdminBaseController'

  ### Popular gems integration

  ## == Authenticate with Basic Auth ==
  config.authenticate_with do
    authenticate_or_request_with_http_basic('Admin Area') do |username, password|
      expected_username = ENV.fetch('ADMIN_USERNAME', 'admin')
      expected_password = ENV.fetch('ADMIN_PASSWORD', 'password')

      ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &&
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end

  config.actions do
    dashboard                     # mandatory
    index                         # mandatory
    new
    export
    bulk_delete
    show
    edit
    delete
    # show_in_app intentionally omitted: this app is config.api_only = true
    # with no conventional (non-namespaced) show route for any admin-exposed
    # model (Site, User, BotRule), so RailsAdmin's generated *_url helper
    # (e.g. bot_rule_url) doesn't exist and every show_in_app click 500s.
  end
end
