module Api
  module V1
    module Admin
      class SitesController < BaseController
        # GET /api/v1/admin/sites
        def index
          @sites = Site.order(created_at: :asc)
          render json: @sites, status: :ok
        end

        # POST /api/v1/admin/sites/:id/reset_ai
        def reset_ai
          @site = Site.find(params[:id])
          reset_daily_usage(@site)
          render json: { message: 'AI recommendation usage limit reset successfully' }, status: :ok
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Site not found' }, status: :not_found
        end

        private

        def reset_daily_usage(site)
          usage_date = 3.hours.ago.to_date
          usage = site.daily_ai_usages.find_or_initialize_by(usage_date: usage_date)
          usage.update!(used_count: 0, reset_at: Time.current)
        end
      end
    end
  end
end
