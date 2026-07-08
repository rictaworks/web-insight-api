module Api
  module V1
    class SitesController < ApplicationController
      before_action :set_site, only: %i[show snippet pageviews heatmap performance]

      # GET /api/v1/sites
      def index
        @sites = current_user.sites.order(created_at: :asc).limit(10)
        render json: @sites, status: :ok
      end

      # GET /api/v1/sites/:id
      def show
        render json: @site, status: :ok
      end

      # POST /api/v1/sites
      def create
        @site = current_user.sites.build(site_params)

        if create_within_limit?
          render_create_result
        else
          render json: { error: 'Maximum site limit reached (10 sites)' }, status: :unprocessable_content
        end
      end

      # GET /api/v1/sites/:id/snippet
      def snippet
        render json: { snippet: @site.generate_snippet }, status: :ok
      end

      # GET /api/v1/sites/:id/pageviews
      def pageviews
        period = params[:period]
        axis = params[:axis]

        return unless valid_enum_param?(period, %w[7d 30d 90d], 'period')
        return unless valid_enum_param?(axis, %w[day week month], 'axis')

        render json: AnalyticsEngine.pageviews(@site, period: period, axis: axis), status: :ok
      end

      # GET /api/v1/sites/:id/heatmap
      def heatmap
        url = params[:url]
        viewport = params[:viewport]

        if url.blank? || !url.is_a?(String)
          render json: { error: 'Invalid or missing url. Parameter is required.' },
                 status: :unprocessable_content
          return
        end
        return unless valid_enum_param?(viewport, %w[desktop mobile], 'viewport')

        render json: AnalyticsEngine.heatmap(@site, url: url, viewport: viewport), status: :ok
      end

      # GET /api/v1/sites/:id/performance
      def performance
        period = params[:period]
        percentile = params[:percentile]

        return unless valid_enum_param?(period, %w[7d 30d 90d], 'period')
        return unless valid_enum_param?(percentile, %w[p50 p75 p95], 'percentile')

        render json: AnalyticsEngine.performance(@site, period: period, percentile: percentile), status: :ok
      end

      private

      # Validates a query param against its allow-list, rendering a 422 and
      # returning false when the value is missing or not permitted. Centralizes
      # the repeated validate-or-render pattern shared by the report actions so
      # each stays small and the class remains within Metrics/ClassLength.
      def valid_enum_param?(value, allowed, label)
        return true if value.present? && allowed.include?(value)

        render json: {
          error: "Invalid or missing #{label}. Allowed values: #{allowed.join(', ')}"
        }, status: :unprocessable_content
        false
      end

      # Serialize concurrent creates for this user so the 10-site cap cannot be
      # bypassed by requests that each observe count < LIMIT before either insert
      # commits. The user-row lock (SELECT ... FOR UPDATE on PostgreSQL) makes the
      # check-and-insert atomic; SQLite dev/test run the block serially. Returns
      # false only when the limit is reached, so @site.save runs inside the lock.
      def create_within_limit?
        within_limit = true
        current_user.with_lock do
          if SitePolicy.new(current_user).create?
            @site.save
          else
            within_limit = false
          end
        end
        within_limit
      end

      def render_create_result
        if @site.persisted?
          render json: @site, status: :created
        else
          render json: { errors: @site.errors.full_messages }, status: :unprocessable_content
        end
      end

      def set_site
        site_exists = Site.exists?(id: params[:id])
        @site = current_user.sites.find_by(id: params[:id])

        return if @site

        if site_exists
          render json: { error: 'Forbidden' }, status: :forbidden
        else
          render json: { error: 'Not Found' }, status: :not_found
        end
      end

      def site_params
        params.require(:site).permit(:name, :url)
      end
    end
  end
end
