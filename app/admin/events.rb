ActiveAdmin.register Event do
  belongs_to :project, optional: true

  actions :index, :show, :destroy

  controller do
    def scoped_collection
      Event.kept.includes(:project)
    end

    def destroy
      resource.discard
      redirect_to admin_events_path, notice: "Event discarded."
    end
  end

  index do
    selectable_column
    column(:id) { |e| link_to e.id, admin_event_path(e.id) }
    column :project do |e|
      link_to e.project.name, admin_project_path(e.project.id)
    end
    column :level
    column :message do |e|
      truncate(e.message, length: 80)
    end
    column :environment
    column :resolved
    column :occurred_at
    actions defaults: false do |e|
      item "View",   admin_event_path(e.id)
      item "Delete", admin_event_path(e.id), "data-turbo-method": "delete", "data-turbo-confirm": "Are you sure?"
    end
  end

  filter :level, as: :select, collection: Event.levels.keys
  filter :environment
  filter :resolved
  filter :message_cont, label: "Message contains"
  filter :occurred_at

  show do
    attributes_table do
      row :id
      row :project do |e|
        link_to e.project.name, admin_project_path(e.project.id)
      end
      row :level
      row :message
      row :environment
      row :fingerprint
      row :resolved
      row :occurred_at
      row "Storage" do |e|
        info = e.chunk_info
        if info.nil?
          "—"
        elsif info[:is_compressed]
          safe_join([
            status_tag("compressed", class: "ok"),
            " in chunk #{info[:chunk_name]} (#{info[:range_start].to_date} → #{info[:range_end].to_date})"
          ])
        else
          safe_join([
            status_tag("hot", class: "warning"),
            " in chunk #{info[:chunk_name]} (#{info[:range_start].to_date} → #{info[:range_end].to_date})"
          ])
        end
      end
      row :backtrace do |e|
        pre e.backtrace
      end
      row :metadata do |e|
        pre JSON.pretty_generate(e.metadata)
      end
    end
  end
end
