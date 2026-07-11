require 'net/http'
require 'uri'
require 'securerandom'

# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
class AiRecommendationService
  class LimitExceededError < StandardError; end
  class LLMError < StandardError; end

  SYSTEM_PROMPT = <<~TEXT.freeze
    You are an AI Web Analyst. Your job is to analyze website performance metrics, user flow funnels, and Core Web Vitals to provide concrete, actionable improvements for the user's website.
    You must output a single, raw JSON object matching the following structure:
    {
      "recommendations": [
        {
          "category": "UX" | "SEO" | "パフォーマンス" | "コンテンツ",
          "priority": 1 | 2 | 3,
          "description": "Concrete advice in Japanese",
          "estimated_impact": "高" | "中" | "低"
        }
      ]
    }
    Constraints:
    1. Do not wrap the JSON output in markdown blocks (e.g. ```json). Output raw JSON.
    2. Provide exactly 2 to 5 recommendations based on the importance and quality of the input data.
    3. The categories must be exactly one of: "UX", "SEO", "パフォーマンス", "コンテンツ".
    4. The description must be in Japanese, clear, specific, and actionable. Do not use generic advice. Refer to the site URL and the actual numbers where appropriate.
    5. Priority 1 is highest priority.
    6. Estimated impact must be one of "高", "中", "低".
  TEXT

  VALID_CATEGORIES = %w[UX SEO パフォーマンス コンテンツ].freeze
  VALID_PRIORITIES = [1, 2, 3].freeze
  VALID_IMPACTS = %w[高 中 低].freeze
  VALID_RECOMMENDATIONS_SIZE = (2..5)

  def initialize(site)
    @site = site
  end

  def generate_recommendations
    usage_date = 3.hours.ago.to_date
    usage = reserve_daily_usage!(usage_date)

    begin
      metrics = collect_metrics
      raw_response = call_llm(metrics)
      recommendations_data = parse_response(raw_response)
      save_recommendations(recommendations_data)
    rescue StandardError => e
      release_daily_usage!(usage)
      raise e
    end
  end

  private

  # Reserves the daily quota slot in a short transaction (no external calls
  # inside the DB lock), so a slow/concurrent Gemini call never holds a
  # connection from the production pool (size 5).
  def reserve_daily_usage!(usage_date)
    DailyAiUsage.transaction do
      usage = find_or_create_usage(usage_date)

      usage.with_lock do
        raise LimitExceededError, 'Daily AI recommendation limit reached' if usage.used_count >= 1

        usage.update!(used_count: usage.used_count + 1)
      end

      usage
    end
  end

  def find_or_create_usage(usage_date)
    # Handle race conditions when creating daily usage record
    @site.daily_ai_usages.find_or_create_by!(usage_date: usage_date)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Gives back the reserved slot if the LLM call or parsing fails, so a
  # failed attempt doesn't consume the user's one-per-day allowance.
  def release_daily_usage!(usage)
    usage.with_lock do
      usage.update!(used_count: [usage.used_count - 1, 0].max)
    end
  end

  def save_recommendations(recommendations_data)
    generated_at = Time.current

    ActiveRecord::Base.transaction do
      recommendations_data.map do |rec|
        @site.ai_recommendations.create!(
          category: rec['category'],
          priority: rec['priority'],
          description: rec['description'],
          estimated_impact: rec['estimated_impact'],
          generated_at: generated_at
        )
      end
    end
  end

  def collect_metrics
    period = '30d'
    pageviews_data = AnalyticsEngine.pageviews(@site, period: period, axis: 'day')
    performance_data = AnalyticsEngine.performance(@site, period: period, percentile: 'p75')
    funnels_data = @site.funnels.map do |funnel|
      AnalyticsEngine.funnel(@site, funnel, period: period)
    end

    {
      site_url: @site.url,
      pageviews_30d: {
        totals: pageviews_data[:totals],
        change_rates: pageviews_data[:change_rates]
      },
      core_web_vitals_p75: performance_data,
      funnels: funnels_data.map { |f| { name: f[:name], completion_rate: f[:completion_rate], steps: f[:steps] } }
    }
  end

  def call_llm(metrics)
    api_key = ENV.fetch('GEMINI_API_KEY', nil)

    raise LLMError, 'Gemini API key is not configured' if api_key.blank?

    llm = Langchain::LLM::GoogleGemini.new(
      api_key: api_key,
      default_options: {
        chat_model: 'gemini-2.5-flash'
      }
    )

    inputs = {
      system_prompt: SYSTEM_PROMPT,
      user_prompt: metrics.to_json
    }

    run_id = SecureRandom.uuid
    log_langsmith_start(run_id, inputs)

    begin
      # `system` is a top-level Gemini API parameter, not a message role —
      # Langchain::LLM::GoogleGemini remaps it to system_instruction and
      # rejects a 'system' entry inside `messages`. Each `messages` entry is
      # passed straight through as a Gemini `contents` item (remap only
      # renames the top-level key; it does not reshape array elements), so it
      # must carry Gemini's own `parts: [{ text: ... }]` shape rather than an
      # OpenAI/Anthropic-style `content:` string, or the real API rejects the
      # request outright. response_format asks Gemini to only emit valid
      # JSON, avoiding markdown-fenced or otherwise non-parseable output from
      # parse_response.
      response = llm.chat(
        system: SYSTEM_PROMPT,
        messages: [
          { role: 'user', parts: [{ text: metrics.to_json }] }
        ],
        response_format: 'application/json'
      )

      output_text = response.chat_completion
      log_langsmith_end(run_id, { output: output_text }, nil)
      output_text
    rescue StandardError => e
      log_langsmith_end(run_id, nil, "#{e.class}: #{e.message}")
      raise e
    end
  end

  def parse_response(raw_response)
    cleaned = raw_response.strip
    cleaned = cleaned.sub(/\A```(?:json)?\n/, '').sub(/\n```\z/, '') if cleaned.start_with?('```')

    parsed = JSON.parse(cleaned)
    raise LLMError, 'Invalid JSON structure from LLM' unless parsed.is_a?(Hash) && parsed.key?('recommendations')

    recommendations = parsed['recommendations']
    validate_recommendations!(recommendations, raw_response)
    recommendations
  rescue JSON::ParserError => e
    raise LLMError, "Failed to parse JSON response: #{e.message}. Raw content: #{raw_response}"
  end

  # Enforces the SYSTEM_PROMPT contract (2-5 well-formed items) so that
  # off-contract JSON — e.g. model drift or prompt-injected site/funnel data
  # coaxing an empty or malformed array — is rejected instead of silently
  # consuming the daily quota for an unusable result.
  def validate_recommendations!(recommendations, raw_response)
    unless recommendations.is_a?(Array) && VALID_RECOMMENDATIONS_SIZE.cover?(recommendations.size)
      raise LLMError, "Recommendations array must contain 2 to 5 items. Raw content: #{raw_response}"
    end

    recommendations.each do |rec|
      next if valid_recommendation?(rec)

      raise LLMError, "Invalid recommendation item from LLM: #{rec.inspect}. Raw content: #{raw_response}"
    end
  end

  def valid_recommendation?(rec)
    rec.is_a?(Hash) &&
      VALID_CATEGORIES.include?(rec['category']) &&
      VALID_PRIORITIES.include?(rec['priority']) &&
      rec['description'].is_a?(String) && rec['description'].strip.present? &&
      VALID_IMPACTS.include?(rec['estimated_impact'])
  end

  # LangSmith Tracing Helpers (Non-blocking using Threads)
  def log_langsmith_start(run_id, inputs)
    api_key = ENV['LANGSMITH_API_KEY'] || ENV.fetch('LANGCHAIN_API_KEY', nil)
    project = ENV['LANGSMITH_PROJECT'] || 'web-insight-api'
    return if api_key.blank?

    Thread.new do
      uri = URI('https://api.smith.langchain.com/runs')
      req = Net::HTTP::Post.new(uri, {
                                  'x-api-key' => api_key,
                                  'Content-Type' => 'application/json'
                                })
      req.body = {
        id: run_id,
        name: 'Generate AI Recommendations',
        run_type: 'chain',
        inputs: inputs,
        start_time: Time.current.utc.iso8601(3),
        project_name: project
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 2
      http.request(req)
    rescue StandardError => e
      Rails.logger.warn "[LangSmith] Failed to log run start: #{e.message}"
    end
  end

  def log_langsmith_end(run_id, outputs, error_message)
    api_key = ENV['LANGSMITH_API_KEY'] || ENV.fetch('LANGCHAIN_API_KEY', nil)
    return if api_key.blank?

    Thread.new do
      uri = URI("https://api.smith.langchain.com/runs/#{run_id}")
      req = Net::HTTP::Patch.new(uri, {
                                   'x-api-key' => api_key,
                                   'Content-Type' => 'application/json'
                                 })
      body = { end_time: Time.current.utc.iso8601(3) }
      if error_message
        body[:error] = error_message
      else
        body[:outputs] = outputs
      end
      req.body = body.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 2
      http.request(req)
    rescue StandardError => e
      Rails.logger.warn "[LangSmith] Failed to log run end: #{e.message}"
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength
