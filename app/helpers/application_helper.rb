module ApplicationHelper
  def sortable_column(column, title = nil)
    title ||= column.titleize
    direction = column == params[:sort] && params[:direction] == "asc" ? "desc" : "asc"
    css_class = column == params[:sort] ? "sortable active" : "sortable"

    # Preserve search parameters
    link_params = {
      sort: column,
      direction: direction,
      q: params[:q],
      column: params[:column],
      page: params[:page]
    }.compact

    link_to dailylogs_path(link_params), data: { turbo_frame: "dailylogs_table" }, class: css_class do
      content = title.dup
      if column == params[:sort]
        icon = params[:direction] == "asc" ? " ▲" : " ▼"
        content += icon
      end
      content.html_safe
    end
  end
end
