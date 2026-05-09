class DashboardEventsChannel < ApplicationCable::Channel
  def subscribed
    org = current_user.organizations.kept.find_by(id: params[:organization_id])
    if org
      stream_for org
    else
      reject
    end
  end
end
