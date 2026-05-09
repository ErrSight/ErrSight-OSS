ActiveAdmin.register Invitation do
  actions :index, :show, :destroy

  belongs_to :organization, optional: true

  index do
    selectable_column
    id_column
    column :organization
    column :email
    column :role
    column :status
    column :invited_by do |inv|
      inv.invited_by.email
    end
    column :expires_at
    column :created_at
    actions
  end

  filter :email
  filter :status, as: :select, collection: Invitation.statuses
  filter :role, as: :select, collection: Invitation.roles
  filter :created_at

  show do
    attributes_table do
      row :id
      row :organization
      row :email
      row :role
      row :status
      row :token
      row :invited_by
      row :expires_at
      row :accepted_at
      row :created_at
    end
  end
end
