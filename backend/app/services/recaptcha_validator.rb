# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
class RecaptchaValidator
  SITEVERIFY_URL = URI('https://www.google.com/recaptcha/api/siteverify')
  OPEN_TIMEOUT_SECONDS = 3
  READ_TIMEOUT_SECONDS = 3

  def self.verify(token, remote_ip = nil)
    secret_key = ENV.fetch('RECAPTCHA_SECRET_KEY', nil)

    if secret_key.blank?
      raise 'RECAPTCHA_SECRET_KEY is required in production environment' if Rails.env.production?

      Rails.logger.warn('RECAPTCHA_SECRET_KEY is blank. Bypassing reCAPTCHA verification.')
      return true

    end

    return false if token.blank?

    begin
      response = Net::HTTP.start(
        SITEVERIFY_URL.host, SITEVERIFY_URL.port,
        use_ssl: SITEVERIFY_URL.scheme == 'https',
        open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS
      ) do |http|
        request = Net::HTTP::Post.new(SITEVERIFY_URL)
        request.set_form_data({ secret: secret_key, response: token, remoteip: remote_ip }.compact)
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("reCAPTCHA API error: response status #{response.code}")
        raise "reCAPTCHA verification API returned non-success: #{response.code}"
      end

      result = JSON.parse(response.body)

      # reCAPTCHA v3: success is true and score is present and >= 0.5.
      # A response without a score (e.g. non-v3 or misconfigured secret) must
      # be rejected rather than silently bypassing the score check.
      success = result['success'] == true && result['score'].present? && result['score'].to_f >= 0.5

      Rails.logger.info("reCAPTCHA verification result: success=#{success}, score=#{result['score']}")
      success
    rescue StandardError => e
      Rails.logger.error("reCAPTCHA verification exception: #{e.message}")
      raise
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
