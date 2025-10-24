module ConstructionOverviewHelper
  def phase_badge(phase)
    color = case phase
            when 'Phase 0' then 'primary'
            when 'Phase 1' then 'success'
            when 'Phase 2' then 'info'
            when 'Phase 3' then 'warning'
            when 'Phase 4' then 'danger'
            else 'secondary'
            end

    content_tag :span, phase, class: "badge badge-#{color}"
  end

  def format_datetime_short(datetime)
    return '-' if datetime.blank?

    # Parse datetime (vem do SQLite como string)
    dt = datetime.is_a?(String) ? Time.parse(datetime) : datetime
    dt.strftime('%m/%d, %I:%M%p')
  rescue StandardError
    datetime.to_s
  end

  def dias_aberto_badge(dias)
    return '-' if dias.blank?

    dias = dias.to_i

    # Badge danger se > 7 dias, warning se 4-7 dias, info se < 4 dias
    if dias > 7
      color = 'danger'
      icon = 'fas fa-exclamation-circle'
    elsif dias >= 4
      color = 'warning'
      icon = 'fas fa-exclamation-triangle'
    else
      color = 'info'
      icon = 'fas fa-clock'
    end

    content_tag :span, class: "badge badge-#{color}" do
      concat content_tag(:i, '', class: icon)
      concat " #{dias}d"
    end
  end
end
