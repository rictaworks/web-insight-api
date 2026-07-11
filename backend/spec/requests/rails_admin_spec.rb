require 'rails_helper'

RSpec.describe 'RailsAdmin', type: :request do
  let(:admin_user) { 'admin' }
  let(:admin_pass) { 'password' }

  before do
    stub_const('ENV', ENV.to_h.merge('ADMIN_USERNAME' => admin_user, 'ADMIN_PASSWORD' => admin_pass))
  end

  describe 'GET /admin' do
    it 'returns 401 when unauthenticated' do
      get '/admin'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'loads the dashboard instead of raising I18n::InvalidLocale when authenticated' do
      # Regression test: config/initializers/rails_admin.rb forces
      # I18n.locale = :ja on every /admin request. Without a registered
      # :ja locale (config/locales/ja.yml), that raises I18n::InvalidLocale
      # and every /admin request 500s even with valid credentials.
      auth = ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass)

      get '/admin', headers: { 'Authorization' => auth }

      expect(response).to have_http_status(:ok)
    end

    it 'does not leak the :ja locale into subsequent requests on the same thread' do
      # Regression test: I18n.locale is thread-local and Puma reuses threads
      # across requests. Forcing it with a bare assignment in
      # RailsAdmin::Config.authenticate_with would leave :ja set for
      # whichever unrelated API request lands on that thread next.
      # config/initializers/rails_admin.rb now scopes it via
      # RailsAdminBaseController's around_action instead.
      auth = ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass)
      original_locale = I18n.locale

      get '/admin', headers: { 'Authorization' => auth }

      expect(I18n.locale).to eq(original_locale)
    end

    it 'renders RailsAdmin UI chrome in Japanese instead of falling back to English' do
      # Regression test: RailsAdmin 3.1 only ships English translations for
      # its own UI strings (menus, buttons, filters, etc.), so forcing :ja
      # without the rails_admin-i18n gem would render everything via the
      # English fallback (or "translation missing: ja...." spans where no
      # fallback is configured), despite CLAUDE.md requiring a Japanese-only
      # admin UI.
      auth = ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass)

      get '/admin', headers: { 'Authorization' => auth }

      expect(response.body).to include('ダッシュボード') # dashboard
      expect(response.body).not_to include('translation missing')
    end

    it 'renders model labels in Japanese instead of falling back to English class names' do
      # Regression test: rails_admin-i18n only translates RailsAdmin's own
      # UI chrome, not the app's model/attribute names — those come from
      # activerecord.models.* / activerecord.attributes.* in
      # config/locales/ja.yml. Without those entries, the sidebar and page
      # titles would show raw English class names like "Site", "User", and
      # "Bot rule", violating the Japanese-only admin UI requirement.
      auth = ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass)

      get '/admin', headers: { 'Authorization' => auth }

      expect(response.body).to include('サイト') # Site
      expect(response.body).to include('ユーザー') # User
      expect(response.body).to include('ボットルール') # Bot rule
    end
  end
end
