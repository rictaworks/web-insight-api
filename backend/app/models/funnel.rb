class Funnel < ApplicationRecord
  belongs_to :site

  # Canonical step schema (see ER 図): an ordered array of
  # {"type" => "url"|"event", "value" => "..."} hashes.
  VALID_STEP_TYPES = %w[url event].freeze

  before_validation :normalize_steps

  validates :name, presence: true
  validate :steps_must_be_valid_array

  private

  # Coerce every step into the canonical {"type", "value"} hash before
  # validation so both the documented object shape and the bare-string
  # shorthand are stored uniformly. A plain string is treated as a URL step
  # (the documented default) and hashes may arrive with symbol or string keys.
  # Non-coercible entries are left untouched so validation can flag them.
  def normalize_steps
    return unless steps.is_a?(Array)

    self.steps = steps.map { |step| normalize_step(step) }
  end

  def normalize_step(step)
    case step
    when String
      { 'type' => 'url', 'value' => step }
    when Hash
      normalized = step.transform_keys(&:to_s)
      { 'type' => normalized['type'].presence || 'url', 'value' => normalized['value'] }
    else
      step
    end
  end

  def steps_must_be_valid_array
    return errors.add(:steps, "can't be blank") if steps.nil?
    return errors.add(:steps, 'must be an array') unless steps.is_a?(Array)

    validate_steps_size
    validate_steps_elements
  end

  def validate_steps_size
    errors.add(:steps, 'must contain between 2 and 20 steps') if steps.size < 2 || steps.size > 20
  end

  def validate_steps_elements
    steps.each_with_index do |step, index|
      message = step_error(step)
      errors.add(:steps, "step #{index + 1} #{message}") if message
    end
  end

  def step_error(step)
    return 'must be a url or event with a non-empty value' unless valid_step_shape?(step)

    # An event step can only ever be satisfied by an event that /events/collect
    # actually accepts, so reject names outside the collectable event types up
    # front instead of saving a funnel whose step always reports zero.
    if step['type'] == 'event' && EventCollector::ALLOWED_EVENT_TYPES.exclude?(step['value'])
      return "event value must be one of: #{EventCollector::ALLOWED_EVENT_TYPES.join(', ')}"
    end

    nil
  end

  def valid_step_shape?(step)
    step.is_a?(Hash) &&
      VALID_STEP_TYPES.include?(step['type']) &&
      step['value'].is_a?(String) && step['value'].present?
  end
end
