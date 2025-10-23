module DailylogsHelper
  def sortable_fmea_column(column)
    direction = params[:fmea_direction] == "asc" ? "desc" : "asc"
    icon = params[:fmea_sort] == column ?
      (params[:fmea_direction] == "asc" ? "fa-sort-up" : "fa-sort-down") :
      "fa-sort"

    link_to(
      "#{column.titleize} <i class='fas #{icon}'></i>".html_safe,
      dailylogs_path(
        # Preserve dailylogs params
        q: params[:q],
        column: params[:column],
        sort: params[:sort],
        direction: params[:direction],
        page: params[:page],
        # FMEA params
        fmea_sort: column,
        fmea_direction: direction,
        fmea_q: params[:fmea_q],
        fmea_column: params[:fmea_column],
        fmea_page: params[:fmea_page]
      ),
      data: { turbo_frame: "dailylogs_fmea_table" }
    )
  end
end
