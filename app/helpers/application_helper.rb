module ApplicationHelper
  include Pagy::Frontend

  def pagy_nav(pagy)
    return "" if pagy.pages <= 1

    html = '<nav class="flex items-center gap-1 text-sm" aria-label="Pagination">'.html_safe

    # Previous
    if pagy.prev
      html += link_to("←", url_for(page: pagy.prev), class: "px-3 py-1.5 rounded-lg bg-gray-800 text-gray-300 hover:bg-gray-700 transition")
    else
      html += content_tag(:span, "←", class: "px-3 py-1.5 rounded-lg bg-gray-800/30 text-gray-600 cursor-not-allowed")
    end

    # Page numbers
    pagy.series.each do |item|
      case item
      when Integer
        html += link_to(item, url_for(page: item), class: "px-3 py-1.5 rounded-lg bg-gray-800 text-gray-300 hover:bg-gray-700 transition")
      when String
        html += content_tag(:span, item.to_i, class: "px-3 py-1.5 rounded-lg bg-indigo-600 text-white font-semibold")
      when :gap
        html += content_tag(:span, "…", class: "px-2 py-1.5 text-gray-600")
      end
    end

    # Next
    if pagy.next
      html += link_to("→", url_for(page: pagy.next), class: "px-3 py-1.5 rounded-lg bg-gray-800 text-gray-300 hover:bg-gray-700 transition")
    else
      html += content_tag(:span, "→", class: "px-3 py-1.5 rounded-lg bg-gray-800/30 text-gray-600 cursor-not-allowed")
    end

    html += "</nav>".html_safe
    html
  end
end
