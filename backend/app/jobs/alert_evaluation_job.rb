class AlertEvaluationJob < ApplicationJob
  queue_as :default

  def perform(site_id)
    site = Site.find_by(id: site_id)
    return unless site

    AlertRuleEvaluator.perform(site)
  end
end
