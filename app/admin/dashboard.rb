# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "System Overview" do
          div class: "attributes_table" do
            table do
              tr { th "Metric"; th "Value" }
              tr { td "Total Users";           td User.count }
              tr { td "Total Projects";        td Project.count }
              tr { td "Total Events";          td Event.kept.count }
              tr { td "Events This Month";     td Event.kept.where("occurred_at >= ?", Date.current.beginning_of_month).count }
              tr { td "Paused Projects";       td Project.where(ingestion_paused: true).count }
              tr { td "Unresolved Errors";     td Event.kept.unresolved.where(level: [ Event.levels[:error], Event.levels[:fatal] ]).count }
            end
          end
        end

        panel "TimescaleDB — events hypertable" do
          stats = TimescaleStats.hypertable
          div class: "attributes_table" do
            table do
              tr { th "Metric"; th "Value" }
              if stats[:available]
                tr { td "Total chunks";          td stats[:total_chunks] }
                tr { td "Compressed chunks";     td stats[:compressed_chunks] }
                tr { td "Uncompressed (hot)";    td stats[:uncompressed_chunks] }
                tr { td "Size on disk";          td number_to_human_size(stats[:total_bytes_on_disk]) }
                tr { td "Uncompressed size of compressed data"; td number_to_human_size(stats[:before_bytes]) }
                tr { td "Compressed size";       td number_to_human_size(stats[:after_bytes]) }
                tr { td "Storage saved";         td number_to_human_size(stats[:bytes_saved]) }
                tr { td "Compression ratio";     td(stats[:ratio] ? "#{stats[:ratio]}x" : "—") }
              else
                tr { td colspan: 2 do
                  "TimescaleDB extension not available on this database."
                end }
              end
            end
          end
        end

        panel "Top Projects by Event Count" do
          table_for Project.includes(:user).order(events_count: :desc).limit(5) do
            column(:name) { |p| link_to p.name, admin_project_path(p.id) }
            column(:user) { |p| p.user.email }
            column(:events_count)
            column(:storage) { |p| number_to_human_size(p.storage_bytes) }
          end
        end
      end

      column do
        panel "Recent Events (last 15)" do
          table_for Event.kept.includes(:project).order(occurred_at: :desc).limit(15) do
            column(:id) { |e| link_to "##{e.id}", admin_event_path(e.id) }
            column(:level)
            column(:message) { |e| truncate(e.message, length: 60) }
            column(:project) { |e| link_to e.project.name, admin_project_path(e.project.id) }
            column(:occurred_at) { |e| time_ago_in_words(e.occurred_at) + " ago" }
          end
        end
      end
    end
  end
end
