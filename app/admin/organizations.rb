ActiveAdmin.register Organization do
  permit_params :name

  controller do
    def scoped_collection
      Organization.with_discarded.includes(:owner, :memberships, :projects)
    end
  end

  index do
    selectable_column
    id_column
    column :name
    column :slug
    column :owner
    column :members_count do |org|
      org.memberships.size
    end
    column :projects_count do |org|
      org.projects.size
    end
    column :discarded_at
    column :created_at
    actions defaults: true do |org|
      if org.discarded?
        item "Restore", restore_admin_organization_path(org.id),
             method: :post,
             data: { confirm: "Restore #{org.name}?" }
      end
    end
  end

  filter :name
  filter :discarded_at
  filter :created_at

  show do
    attributes_table do
      row :id
      row :name
      row :slug
      row :owner
      row :discarded_at
      row :created_at
      row :updated_at
    end

    panel "Members" do
      table_for organization.memberships.includes(:user) do
        column :id
        column :user do |m|
          link_to m.user.email, admin_user_path(m.user)
        end
        column :role
        column :created_at
      end
    end

    panel "Projects" do
      table_for organization.projects do
        column :id
        column :name
        column :events_count
        column :storage_bytes do |p|
          number_to_human_size(p.storage_bytes)
        end
        column :actions do |p|
          link_to "View", admin_project_path(p)
        end
      end
    end

    panel "Pending Invitations" do
      table_for organization.invitations.pending do
        column :id
        column :email
        column :role
        column :invited_by do |inv|
          inv.invited_by.email
        end
        column :expires_at
      end
    end
  end

  form do |f|
    f.inputs "Organization Details" do
      f.input :name
    end
    f.actions
  end

  action_item :restore_organization, only: :show do
    next unless organization.discarded?
    text_node button_to("Restore Organization", restore_admin_organization_path(organization.id),
                        method: :post,
                        authenticity_token: form_authenticity_token,
                        data: { confirm: "Restore #{organization.name}?" },
                        style: "background:#27ae60; color:#fff; padding:4px 12px; border-radius:3px; text-decoration:none; border:none; cursor:pointer;")
  end

  # Un-discards the organization. If its owner is also discarded (the common
  # case when the org was cascade-discarded via account deletion), restore the
  # owner too — otherwise the org comes back but is invisible to the policy
  # scope and nobody can access it.
  member_action :restore, method: :post do
    unless resource.discarded?
      redirect_to admin_organization_path(resource.id), alert: "Organization is not discarded." and return
    end

    owner_restored = false
    ActiveRecord::Base.transaction do
      if resource.owner&.discarded?
        resource.owner.undiscard
        owner_restored = true
      end
      resource.undiscard
    end

    msg = "Restored organization \"#{resource.name}\""
    msg += " (owner \"#{resource.owner.email}\" also restored)" if owner_restored
    msg += "."
    redirect_to admin_organization_path(resource.id), notice: msg
  end
end
