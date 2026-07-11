# Configured as RailsAdmin's parent_controller (see
# config/initializers/rails_admin.rb) so every RailsAdmin-generated
# controller inherits this. I18n.locale is thread-local and Puma reuses
# threads across requests, so assigning I18n.locale = :ja directly (the
# previous approach, in the authenticate_with block) would leak the admin
# locale into the next unrelated API request handled on the same thread.
# Scoping it to this around_action instead restores the prior locale as
# soon as this request finishes, and it wraps _authenticate! too since
# RailsAdmin::ApplicationController defines that before_action in a
# subclass of this one.
# rubocop:disable Rails/ApplicationController -- our ApplicationController is
# ActionController::API (config.api_only = true) and can't render RailsAdmin's
# HTML views, so this intentionally subclasses ActionController::Base instead.
class RailsAdminBaseController < ActionController::Base
  around_action { |_controller, action| I18n.with_locale(:ja, &action) }
end
# rubocop:enable Rails/ApplicationController
