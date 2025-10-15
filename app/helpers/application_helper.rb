module ApplicationHelper
  def sortable_column(column, title = nil)
    title ||= column.titleize

    # Determine if this column is currently sorted
    is_sorted = column == params[:sort]
    is_default_sort = column == "datecreated" && params[:sort].blank?

    # Calculate next direction
    if is_sorted
      direction = params[:direction] == "asc" ? "desc" : "asc"
    elsif is_default_sort
      direction = "asc" # Currently sorted DESC by default, so next click is ASC
    else
      direction = "asc"
    end

    # CSS class for active state
    css_class = (is_sorted || is_default_sort) ? "sortable active" : "sortable"

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

      # Show sort indicator
      if is_sorted
        icon = params[:direction] == "asc" ? " ▲" : " ▼"
        content += icon
      elsif is_default_sort
        content += " ▼" # Default sort is DESC
      end

      content.html_safe
    end
  end

  # Date columns that should be formatted with abbreviated year
  DATE_COLUMNS = %w[datecreated servicedate dateonly enddate startdate created_at updated_at].freeze

  # Format table values based on column type
  # Date columns: yy-mm-dd hh:mm format
  # Other columns: regular string with truncation
  def format_table_value(column, value)
    return "" if value.nil?

    # Format date/datetime columns with abbreviated year
    if DATE_COLUMNS.include?(column.to_s) && value.respond_to?(:strftime)
      value.strftime("%y-%m-%d %H:%M")
    else
      value.to_s.truncate(350)
    end
  end
end
