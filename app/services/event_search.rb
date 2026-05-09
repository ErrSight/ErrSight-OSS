class EventSearch
  ALLOWED_RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze

  def initialize(user, params)
    @user   = user
    @params = params
  end

  def accessible_projects
    @accessible_projects ||= @user.accessible_projects.order(:name)
  end

  def relation
    scope = EventRepository.kept_for_project_ids(scoped_project_ids).includes(:project)
    apply_filters(scope).order(occurred_at: :desc)
  end

  def scoped_project_ids
    ids = accessible_projects.pluck(:id)
    requested = @params[:project_id].presence
    return ids unless requested
    id = requested.to_i
    ids.include?(id) ? [ id ] : ids
  end

  private

  def apply_filters(scope)
    scope = scope.for_environment(@params[:environment])
    scope = scope.for_level(@params[:level])
    scope = scope.for_release(@params[:release])
    scope = scope.for_tag(@params[:tag_key], @params[:tag_value])
    scope = scope.for_keyword(@params[:q])
    scope = scope.where(resolved: @params[:resolved] == "true") if %w[true false].include?(@params[:resolved].to_s)
    if (duration = ALLOWED_RANGES[@params[:range].to_s])
      scope = scope.where(occurred_at: duration.ago..Time.current)
    end
    scope
  end
end
