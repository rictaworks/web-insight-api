module Api
  module V1
    module Admin
      class BotRulesController < BaseController
        # PUT /api/v1/admin/bot_rules
        def update
          keywords = params[:keywords]
          unless keywords.is_a?(Array) && keywords.all?(String)
            return render json: { error: 'Invalid payload: keywords must be an array of strings' },
                          status: :unprocessable_content
          end

          sanitized = sanitize_keywords(keywords)
          return render_empty_keywords_error if sanitized.empty?

          update_bot_rules(sanitized)
          render json: { message: 'Bot rules updated successfully', keywords: BotRule.pluck(:pattern) }, status: :ok
        end

        private

        def sanitize_keywords(keywords)
          keywords.map(&:strip).compact_blank.uniq
        end

        # An empty rule set would be indistinguishable from a not-yet-seeded
        # table (BotDetector falls back to its defaults in that case), so a
        # request that would leave zero rules is rejected outright rather
        # than silently reverting to the default keyword list.
        def render_empty_keywords_error
          render json: { error: 'Invalid payload: at least one keyword is required' }, status: :unprocessable_content
        end

        # Cache invalidation lives on BotRule (after_commit), not here, so it
        # also covers edits made through RailsAdmin's generic UI rather than
        # only this bulk-update endpoint.
        def update_bot_rules(sanitized)
          ActiveRecord::Base.transaction do
            BotRule.delete_all
            sanitized.each do |pattern|
              BotRule.create!(pattern: pattern)
            end
          end
        end
      end
    end
  end
end
