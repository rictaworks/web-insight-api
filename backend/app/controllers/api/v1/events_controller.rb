# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
module Api
  module V1
    class EventsController < ApplicationController
      skip_before_action :authenticate_user!

      # POST /api/v1/events/collect
      def collect
        site_id = request.headers['X-Site-Id']

        # Parse request JSON payload safely
        payload = begin
          JSON.parse(request.raw_post || '{}')
        rescue JSON::ParserError
          {}
        end

        event = EventCollector.collect(
          payload,
          site_id: site_id,
          fallback_user_agent: request.user_agent,
          ip: request.remote_ip,
          fallback_referrer: request.referer
        )

        render json: { id: event.id, status: 'ok' }, status: :ok
      rescue EventCollector::ValidationError => e
        Rails.logger.warn("EventsController validation error: #{LogSanitizer.strip_control_characters(e.message)}")
        render json: { error: e.message }, status: :bad_request
      rescue StandardError => e
        Rails.logger.error("EventsController error: #{e.class} - #{LogSanitizer.strip_control_characters(e.message)}")
        if Rails.env.production?
          render json: { error: 'Internal Server Error' }, status: :internal_server_error
        else
          render json: { error: e.message }, status: :internal_server_error
        end
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
