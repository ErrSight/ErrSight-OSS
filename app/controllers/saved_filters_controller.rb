class SavedFiltersController < ApplicationController
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  def create
    @saved_filter = current_user.saved_filters.build(
      name:    params[:name],
      filters: filters_param
    )
    if @saved_filter.save
      redirect_to search_path(@saved_filter.to_params), notice: "Filter saved as “#{@saved_filter.name}”."
    else
      redirect_to search_path, alert: @saved_filter.errors.full_messages.to_sentence
    end
  end

  def destroy
    filter = current_user.saved_filters.find_by(id: params[:id])
    filter&.destroy
    redirect_to search_path, notice: "Filter removed."
  end

  private

  # Permit only the known filter keys — `to_unsafe_h` would accept arbitrary
  # user input into a JSONB column and bypass Strong Parameters entirely.
  # params[:filters] is always wrapped in ActionController::Parameters by Rails,
  # so a plain-Hash branch would be unreachable.
  def filters_param
    raw = params[:filters]
    return {} unless raw.is_a?(ActionController::Parameters)
    raw.permit(*SavedFilter::ALLOWED_KEYS).to_h
  end
end
