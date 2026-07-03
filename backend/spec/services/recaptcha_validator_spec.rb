require 'rails_helper'

RSpec.describe RecaptchaValidator do
  let(:secret_key) { 'test_secret_key' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RECAPTCHA_SECRET_KEY', nil).and_return(secret_key)
  end

  def stub_siteverify(body_hash, response_class: Net::HTTPOK, status: '200')
    response = response_class.new('1.1', status, 'reason')
    allow(response).to receive(:body).and_return(body_hash.to_json)
    http = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  describe '.verify' do
    it 'returns false when the token is blank' do
      expect(described_class.verify('')).to be(false)
    end

    it 'returns true when success is true and the score meets the 0.5 threshold' do
      stub_siteverify({ 'success' => true, 'score' => 0.9 })

      expect(described_class.verify('token')).to be(true)
    end

    it 'returns false when success is true but the score is below the threshold' do
      stub_siteverify({ 'success' => true, 'score' => 0.3 })

      expect(described_class.verify('token')).to be(false)
    end

    it 'returns false when success is true but the score is missing from the response' do
      stub_siteverify({ 'success' => true })

      expect(described_class.verify('token')).to be(false)
    end

    it 'returns false when success is false' do
      stub_siteverify({ 'success' => false, 'score' => 0.9 })

      expect(described_class.verify('token')).to be(false)
    end

    it 'raises when the siteverify API responds with a non-success status' do
      stub_siteverify({ 'error-codes' => ['invalid-input-secret'] }, response_class: Net::HTTPBadRequest, status: '400')

      expect { described_class.verify('token') }.to raise_error(/non-success/)
    end

    it 'opens the connection with explicit open/read timeouts so a slow siteverify call cannot hang indefinitely' do
      stub_siteverify({ 'success' => true, 'score' => 0.9 })

      described_class.verify('token')

      expect(Net::HTTP).to have_received(:start).with(
        RecaptchaValidator::SITEVERIFY_URL.host,
        RecaptchaValidator::SITEVERIFY_URL.port,
        hash_including(
          open_timeout: RecaptchaValidator::OPEN_TIMEOUT_SECONDS,
          read_timeout: RecaptchaValidator::READ_TIMEOUT_SECONDS
        )
      )
    end
  end
end
