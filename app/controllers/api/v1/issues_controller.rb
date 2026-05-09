module Api
  module V1
    class IssuesController < BaseController
      self.required_scope = :read

      def show
        fingerprint = params[:fingerprint].to_s
        summary = EventRepository.issue_summary(project: @project, fingerprint: fingerprint)

        unless summary
          return render json: { error: "Issue not found" }, status: :not_found
        end

        issue = @project.issues.find_by(fingerprint: fingerprint)

        render json: {
          data: {
            fingerprint:    fingerprint,
            occurrences:    summary[:occurrences],
            affected_users: summary[:affected_users],
            first_seen:     summary[:first_seen]&.iso8601,
            last_seen:      summary[:last_seen]&.iso8601,
            last_message:   summary[:last_message],
            level:          summary[:level],
            all_resolved:   summary[:all_resolved],
            assigned_to:    issue&.assigned_to&.email,
            external_url:   issue&.external_url
          }
        }
      end
    end
  end
end
