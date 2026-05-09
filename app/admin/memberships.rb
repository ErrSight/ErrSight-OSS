ActiveAdmin.register Membership do
  permit_params :role

  belongs_to :organization, optional: true

  controller do
    def scoped_collection
      super.includes(:organization, :user)
    end
  end

  index do
    selectable_column
    id_column
    column :organization
    column :user do |m|
      link_to m.user.email, admin_user_path(m.user)
    end
    column :role
    column :created_at
    actions
  end

  filter :role, as: :select, collection: Membership.roles
  filter :created_at

  show do
    attributes_table do
      row :id
      row :organization
      row :user
      row :role
      row :created_at
      row :updated_at
    end
  end

  form do |f|
    f.inputs "Membership Details" do
      f.input :role, as: :select, collection: Membership.roles.keys
    end
    f.actions
  end
end
