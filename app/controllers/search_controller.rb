class SearchController < ApplicationController
  skip_after_action :verify_policy_scoped, only: [ :show ]
  skip_after_action :verify_authorized, only: [ :show ]

  def show
    @search = EventSearch.new(current_user, search_params)
    @accessible_projects = @search.accessible_projects
    @pagy, @events = pagy(@search.relation, items: 50)
    @saved_filters = current_user.saved_filters.order(:name)
    @releases = EventRepository.releases_for_project_ids(@search.scoped_project_ids)

    if search_params.except(:range).values.any?(&:present?)
    end
  end

  private

  def search_params
    params.permit(:q, :level, :environment, :release, :tag_key, :tag_value,
                  :project_id, :resolved, :range)
  end
end
