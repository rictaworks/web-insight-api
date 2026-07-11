module Api
  module V1
    class AlertRulesController < ApplicationController
      before_action :set_site
      before_action :set_alert_rule, only: %i[update]

      # GET /api/v1/sites/:site_id/alert_rules
      def index
        render json: @site.alert_rules.order(created_at: :asc), status: :ok
      end

      # POST /api/v1/sites/:site_id/alert_rules
      def create
        @alert_rule = @site.alert_rules.build(alert_rule_params)

        if @alert_rule.save
          render json: @alert_rule, status: :created
        else
          render json: { errors: @alert_rule.errors.full_messages }, status: :unprocessable_content
        end
      end

      # PUT/PATCH /api/v1/sites/:site_id/alert_rules/:id
      def update
        if @alert_rule.update(alert_rule_params)
          render json: @alert_rule, status: :ok
        else
          render json: { errors: @alert_rule.errors.full_messages }, status: :unprocessable_content
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

      def set_alert_rule
        @alert_rule = @site.alert_rules.find_by(id: params[:id])
        return if @alert_rule

        alert_rule_exists = AlertRule.exists?(id: params[:id])
        if alert_rule_exists
          render json: { error: 'Forbidden' }, status: :forbidden
        else
          render json: { error: 'Not Found' }, status: :not_found
        end
      end

      def alert_rule_params
        require_object_params(:alert_rule).permit(:metric, :condition, :threshold, :cooldown_min)
      end
    end
  end
end
