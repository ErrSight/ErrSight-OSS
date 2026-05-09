ActiveAdmin.register User do
  permit_params :email, :name, :password, :password_confirmation

  config.action_items.reject! { |item| item.name == :destroy }

  controller do
    def scoped_collection
      User.includes(:organizations)
    end

    def update
      if params[:user][:password].blank? && params[:user][:password_confirmation].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      end
      super
    end

    def destroy
      if resource == current_user
        redirect_to admin_user_path(resource.id), alert: "You cannot delete your own account."
        return
      end
      resource.discard
      redirect_to admin_users_path, notice: "User deleted successfully."
    end
  end

  index do
    selectable_column
    column(:id) { |u| link_to u.id, admin_user_path(u.id) }
    column :email
    column :name
    column :admin
    column("Organizations") { |u| u.organizations.pluck(:name).join(", ") }
    column :projects_count do |u|
      u.projects.size
    end
    column :discarded_at
    column :created_at
    actions defaults: false do |u|
      item "View", admin_user_path(u.id)
      item "Edit", edit_admin_user_path(u.id)
      if !u.discarded? && !u.admin? && u != current_user
        item "Become", become_admin_user_path(u.id),
             method: :post,
             data: { confirm: "Sign in as #{u.email}?" }
      end
      if u.discarded?
        item "Restore", restore_admin_user_path(u.id),
             method: :post,
             data: { confirm: "Restore #{u.email} and their discarded solo-owned organizations?" }
      else
        item "Delete", destroy_user_admin_user_path(u.id),
             method: :post,
             data: { confirm: "Are you sure? This will permanently delete the user and all their projects." }
      end
    end
  end

  filter :email
  filter :admin
  filter :discarded_at
  filter :created_at

  show do
    attributes_table do
      row :id
      row :email
      row :name
      row :admin
      row :discarded_at
      row :created_at
      row :updated_at
    end

    panel "Organizations" do
      table_for user.memberships.includes(:organization) do
        column :organization do |m|
          link_to m.organization.name, admin_organization_path(m.organization)
        end
        column :role
      end
    end

    panel "Projects" do
      table_for user.projects do
        column :id
        column :name
        column :events_count
        column :storage_bytes do |p|
          number_to_human_size(p.storage_bytes)
        end
        column :ingestion_paused
        column :created_at
        column :actions do |p|
          link_to "View", admin_project_path(p.id)
        end
      end
    end
  end

  form do |f|
    f.inputs "User Details" do
      f.input :email
      f.input :name
    end
    f.inputs "Change Password (leave blank to keep current)" do
      f.input :password, required: false, input_html: { autocomplete: "new-password" }
      f.input :password_confirmation, required: false, input_html: { autocomplete: "new-password" }
    end
    f.actions
  end

  action_item :delete_user, only: :show do
    next if user == current_user || user.discarded?
    text_node button_to("Delete User", destroy_user_admin_user_path(user.id),
                        method: :post,
                        authenticity_token: form_authenticity_token,
                        data: { confirm: "Are you sure? This will permanently delete the user and all their projects." },
                        style: "background:#c0392b; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
  end

  action_item :restore_user, only: :show do
    next unless user.discarded?
    text_node button_to("Restore User", restore_admin_user_path(user.id),
                        method: :post,
                        authenticity_token: form_authenticity_token,
                        data: { confirm: "Restore #{user.email} and their discarded solo-owned organizations?" },
                        style: "background:#27ae60; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
  end

  member_action :become, method: :post do
    if resource == current_user
      redirect_to admin_user_path(resource.id), alert: "You are already signed in as this user." and return
    end
    if resource.admin?
      redirect_to admin_user_path(resource.id), alert: "Impersonating another admin is not allowed." and return
    end
    if resource.discarded?
      redirect_to admin_user_path(resource.id), alert: "Cannot impersonate a deleted user." and return
    end

    Rails.logger.info "[impersonation] admin_id=#{current_user.id} became user_id=#{resource.id}"
    session[:true_admin_id] = current_user.id
    bypass_sign_in(resource, scope: :user)
    redirect_to authenticated_root_path, notice: "You are now signed in as #{resource.email}."
  end

  action_item :become_user, only: :show do
    next if user == current_user || user.admin? || user.discarded?
    text_node button_to("Become User", become_admin_user_path(user.id),
                        method: :post,
                        authenticity_token: form_authenticity_token,
                        data: { confirm: "Sign in as #{user.email}? You'll see the app from their perspective." },
                        style: "background:#2c3e50; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
  end

  member_action :promote_admin, method: :post do
    if resource == current_user
      redirect_to admin_user_path(resource.id), alert: "You cannot change your own admin status."
      return
    end
    resource.update!(admin: !resource.admin?)
    redirect_to admin_user_path(resource.id), notice: "Admin status toggled."
  end

  member_action :destroy_user, method: :post do
    if resource == current_user
      redirect_to admin_user_path(resource.id), alert: "You cannot delete your own account."
      return
    end
    resource.discard
    redirect_to admin_users_path, notice: "User \"#{resource.email}\" deleted successfully."
  end

  # Un-discards the user and their solo-owned organizations that were discarded
  # as part of the account deletion cascade. Orgs the admin wants to keep
  # deleted can be re-discarded individually — this restore is the common case.
  member_action :restore, method: :post do
    unless resource.discarded?
      redirect_to admin_user_path(resource.id), alert: "User is not discarded." and return
    end

    restored_orgs = []
    ActiveRecord::Base.transaction do
      resource.undiscard
      resource.owned_organizations.discarded.find_each do |org|
        org.undiscard
        restored_orgs << org
      end
    end

    msg = "Restored user \"#{resource.email}\""
    msg += " and #{view_context.pluralize(restored_orgs.size, 'organization')}" if restored_orgs.any?
    msg += "."
    redirect_to admin_user_path(resource.id), notice: msg
  end
end
