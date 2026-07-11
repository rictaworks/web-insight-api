require 'rails_helper'

RSpec.describe 'config/initializers/require_admin_credentials.rb' do
  subject(:load_initializer) do
    load Rails.root.join('config/initializers/require_admin_credentials.rb')
  end

  context 'when running in production' do
    before { allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production')) }

    it 'raises when ADMIN_USERNAME is unset' do
      env = ENV.to_h.merge('ADMIN_PASSWORD' => 'secret')
      env.delete('ADMIN_USERNAME')
      stub_const('ENV', env)

      expect { load_initializer }.to raise_error(/ADMIN_USERNAME and ADMIN_PASSWORD/)
    end

    it 'raises when ADMIN_PASSWORD is unset' do
      env = ENV.to_h.merge('ADMIN_USERNAME' => 'ops')
      env.delete('ADMIN_PASSWORD')
      stub_const('ENV', env)

      expect { load_initializer }.to raise_error(/ADMIN_USERNAME and ADMIN_PASSWORD/)
    end

    it 'does not raise when both are set' do
      stub_const('ENV', ENV.to_h.merge('ADMIN_USERNAME' => 'ops', 'ADMIN_PASSWORD' => 'secret'))

      expect { load_initializer }.not_to raise_error
    end
  end

  context 'when running outside production' do
    it 'does not raise even when both are unset, so local admin/password fallback stays testable' do
      env = ENV.to_h
      env.delete('ADMIN_USERNAME')
      env.delete('ADMIN_PASSWORD')
      stub_const('ENV', env)

      expect { load_initializer }.not_to raise_error
    end
  end
end
