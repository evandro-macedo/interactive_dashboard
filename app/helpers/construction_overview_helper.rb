module ConstructionOverviewHelper
  def phase_badge(phase)
    # Usar classes customizadas com cores claras
    color_class = case phase
                  when 'Phase 0' then 'badge-phase-0'
                  when 'Phase 1' then 'badge-phase-1'
                  when 'Phase 2' then 'badge-phase-2'
                  when 'Phase 3' then 'badge-phase-3'
                  when 'Phase 4' then 'badge-phase-4'
                  else 'badge-secondary'
                  end

    content_tag :span, phase, class: "badge #{color_class}"
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

  def days_open_badge(days)
    return '-' if days.blank?

    days = days.to_i

    # Badge com cores baseadas em tempo: verde (<15), amarelo (15-30), laranja (30-60), vermelho (>60)
    if days > 60
      color = 'danger'
      icon = 'fas fa-exclamation-circle'
    elsif days > 30
      color = 'orange'  # Usar CSS customizado para laranja
      icon = 'fas fa-exclamation-triangle'
    elsif days >= 15
      color = 'warning'
      icon = 'fas fa-clock'
    else
      color = 'success'
      icon = 'fas fa-check-circle'
    end

    content_tag :span, class: "badge badge-#{color}" do
      concat content_tag(:i, '', class: icon)
      concat " #{days} dias"
    end
  end

  def status_badge(status)
    return '-' if status.blank?

    # Normalizar status para lowercase para comparação
    status_lower = status.to_s.downcase.strip

    # Mapear status para cores (baseado em 30 status identificados)
    color = case status_lower
            # Verde (success): Itens concluídos/aprovados
            when 'inspection approved', 'inspection validated', 'delivered',
                 'rework checklist done', 'repair done', 'inspection waived'
              'success'

            # Azul (primary): Itens agendados/prontos
            when 'scheduled', 'ready to inspect', 'requested',
                 'rework pre scheduled', 'rework scheduled'
              'primary'

            # Amarelo (warning): Itens em andamento/atrasados
            when 'in progress', 'rework in progress', 'delayed',
                 'rework delayed', 'rescheduled', 'rework reschedule',
                 'not started', 'rework not started', 'ordered'
              'warning'

            # Vermelho (danger): Itens reprovados/problemáticos
            when 'inspection disapproved', 'report', 'canceled',
                 'inspection partial approved', 'rework requested'
              'danger'

            # Cinza (secondary): Outros status/informativos
            else
              'secondary'
            end

    content_tag :span, status, class: "badge badge-#{color}"
  end
end
