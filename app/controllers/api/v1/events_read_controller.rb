module Api
  module V1
    class EventsReadController < BaseController
      self.required_scope = :read

      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 25

      def index
        resolved_param = nil
        if params[:resolved].present?
          resolved_param = ActiveModel::Type::Boolean.new.cast(params[:resolved])
        end

        scope = EventRepository.filtered(
          project:     @project,
          environment: params[:environment],
          level:       params[:level],
          fingerprint: params[:fingerprint],
          release:     params[:release],
          resolved:    resolved_param,
          since:       parse_time(params[:since]),
          before:      parse_time(params[:before])
        )

        per_page = [ [ params[:per_page].to_i, 1 ].max, MAX_PER_PAGE ].min
        per_page = DEFAULT_PER_PAGE if params[:per_page].blank?
        page     = [ params[:page].to_i, 1 ].max

        events = scope.order(occurred_at: :desc).limit(per_page).offset((page - 1) * per_page)

        render json: {
          data: events.map { |e| serialize_event(e) },
          page: page,
          per_page: per_page
        }
      end

      def show
        event = EventRepository.find_kept_for_project!(project: @project, id: params[:id])
        render json: { data: serialize_event(event, full: true) }
      end

      private

      def parse_time(value)
        return nil if value.blank?
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def serialize_event(event, full: false)
        base = {
          id:             event.id,
          level:          event.level,
          message:        event.message,
          environment:    event.environment,
          fingerprint:    event.fingerprint,
          release:        event.release,
          occurred_at:    event.occurred_at&.iso8601,
          resolved:       event.resolved,
          is_regression:  event.is_regression,
          user_identifier: event.user_identifier,
          tags:           event.tags
        }
        return base unless full
        base.merge(
          backtrace:    event.backtrace,
          metadata:     event.metadata,
          user_context: event.user_context,
          breadcrumbs:  event.breadcrumbs
        )
      end
    end
  end
end
