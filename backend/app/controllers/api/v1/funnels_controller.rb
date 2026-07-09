module Api
  module V1
    class FunnelsController < ApplicationController
      before_action :set_site
      before_action :set_funnel, only: %i[show]

      # GET /api/v1/sites/:site_id/funnels
      def index
        @funnels = @site.funnels.order(created_at: :asc)
        render json: @funnels, status: :ok
      end

      # GET /api/v1/sites/:site_id/funnels/:id
      def show
        period = params[:period] || '30d'
        return unless valid_enum_param?(period, %w[7d 30d 90d], 'period')

        result = AnalyticsEngine.funnel(@site, @funnel, period: period)
        render json: result, status: :ok
      end

      # POST /api/v1/sites/:site_id/funnels
      def create
        @funnel = @site.funnels.build(funnel_params)

        if @funnel.save
          render json: @funnel, status: :created
        else
          render json: { errors: @funnel.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def set_site
        site_exists = Site.exists?(id: params[:site_id])
        @site = current_user.sites.find_by(id: params[:site_id])

        return if @site

        if site_exists
          render json: { error: 'Forbidden' }, status: :forbidden
        else
          render json: { error: 'Not Found' }, status: :not_found
        end
      end

      def set_funnel
        @funnel = @site.funnels.find_by(id: params[:id])
        return if @funnel

        funnel_exists = Funnel.exists?(id: params[:id])
        if funnel_exists
          render json: { error: 'Forbidden' }, status: :forbidden
        else
          render json: { error: 'Not Found' }, status: :not_found
        end
      end

      def valid_enum_param?(value, allowed, label)
        return true if value.present? && allowed.include?(value)

        render json: {
          error: "Invalid or missing #{label}. Allowed values: #{allowed.join(', ')}"
        }, status: :unprocessable_content
        false
      end

      def funnel_params
        permitted = require_object_params(:funnel).permit(:name)
        permitted[:steps] = permitted_steps
        permitted
      end

      # Steps may arrive as bare strings (URL shorthand) or as the documented
      # {type, value} objects. permit(steps: []) only whitelists scalars and
      # would silently drop every object step, so permit each shape explicitly.
      def permitted_steps
        raw = raw_steps
        return raw unless raw.is_a?(Array)

        raw.map { |step| whitelist_step(step) }
      end

      # Read steps from the raw JSON body so null entries survive: Rails'
      # deep_munge strips nulls out of arrays in `params`, which would otherwise
      # turn an invalid ["/", null, "/checkout"] into a shorter valid two-step
      # array and silently persist a different funnel than the client submitted.
      # Accept both the wrapped ({"funnel": {"steps": ...}}) and the documented
      # top-level ({"steps": ...}) shapes; ParamsWrapper only backfills
      # params[:funnel], not the raw body, so the top-level key must be read here.
      # Fall back to `params` for non-JSON or unparseable bodies.
      def raw_steps
        return params.dig(:funnel, :steps) unless request.media_type == 'application/json'

        body = JSON.parse(request.raw_post)
        return params.dig(:funnel, :steps) unless body.is_a?(Hash)

        body.dig('funnel', 'steps') || body['steps']
      rescue JSON::ParserError
        params.dig(:funnel, :steps)
      end

      # Whitelist a single step down to a plain {type, value} hash (or pass a
      # non-hash entry through untouched so the model can flag it).
      def whitelist_step(step)
        case step
        when ActionController::Parameters
          step.permit(:type, :value).to_h
        when Hash
          step.slice('type', 'value')
        else
          step
        end
      end
    end
  end
end
