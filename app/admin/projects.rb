ActiveAdmin.register Project do
  belongs_to :user, optional: true

  permit_params :name, :ingestion_paused, :admin_paused

  controller do
    def scoped_collection
      super.includes(:user)
    end

    def find_resource
      Project.find(params[:id])
    end
  end

  index do
    selectable_column
    column(:id) { |p| link_to p.id, admin_project_path(p.id) }
    column :name
    column :user do |p|
      link_to p.user.email, admin_user_path(p.user.id)
    end
    column :events_count
    column :storage_bytes do |p|
      number_to_human_size(p.storage_bytes)
    end
    column :ingestion_paused
    column :created_at
    actions defaults: false do |p|
      item "View",   admin_project_path(p.id)
      item "Edit",   edit_admin_project_path(p.id)
      item "Delete", confirm_delete_admin_project_path(p.id)
    end
  end

  filter :name
  filter :ingestion_paused
  filter :user_email, as: :string, label: "User Email"
  filter :created_at

  show do
    attributes_table do
      row :id
      row :name
      row :slug
      row(:api_key) { |p| "elp_...#{p.api_key.last(4)}" }
      row :user do |p|
        link_to p.user.email, admin_user_path(p.user.id)
      end
      row :events_count
      row :storage_bytes do |p|
        number_to_human_size(p.storage_bytes)
      end
      row :ingestion_paused
      row :created_at
      row :updated_at
    end

    panel "Usage by Month" do
      table_for project.usages.order(month: :desc) do
        column :month
        column :events_count
        column :storage_bytes do |u|
          number_to_human_size(u.storage_bytes)
        end
      end
    end
  end

  form do |f|
    f.inputs "Project Settings" do
      f.input :name
      f.input :ingestion_paused
    end
    f.actions
  end

  config.remove_action_item :destroy

  action_item :destroy, only: :show do
    link_to "Delete Project", confirm_delete_admin_project_path(project.id),
            class: "action_item_button"
  end

  action_item :pause_ingestion, only: :show do
    if project.ingestion_paused?
      text_node button_to("Resume Ingestion", resume_ingestion_admin_project_path(project.id),
                          method: :post,
                          authenticity_token: form_authenticity_token,
                          style: "background:#27ae60; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
    else
      text_node button_to("Pause Ingestion", pause_ingestion_admin_project_path(project.id),
                          method: :post,
                          authenticity_token: form_authenticity_token,
                          style: "background:#e67e22; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
    end
  end

  member_action :confirm_delete, method: :get do
    # Renders a simple confirmation page; avoids JS requirement in index
  end

  member_action :do_delete, method: :post do
    name = resource.name
    resource.destroy!
    redirect_to admin_projects_path, notice: "Project \"#{name}\" deleted."
  end

  member_action :pause_ingestion, method: :post do
    resource.update!(ingestion_paused: true, admin_paused: true)
    redirect_to admin_project_path(resource.id), notice: "Ingestion paused."
  end

  member_action :resume_ingestion, method: :post do
    resource.update!(ingestion_paused: false, admin_paused: false)
    redirect_to admin_project_path(resource.id), notice: "Ingestion resumed."
  end
end
