import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js/auto"

// Registrar todos os componentes do Chart.js
Chart.register(...registerables)

export default class extends Controller {
  static values = {
    phaseData: Array  // Query 1: phase_summary
  }

  static targets = ["canvas"]

  connect() {
    this.initChart()
  }

  initChart() {
    // Extrair dados da Query 1
    const labels = this.phaseDataValue.map(p => p.phase_atual)
    const data = this.phaseDataValue.map(p => parseInt(p.total_casas))
    const percentages = this.phaseDataValue.map(p => p.percentual)

    // Paleta CLARA: tons pastéis para melhor legibilidade
    const colors = {
      'Phase 0': '#5b6b9f',  // Azul suave
      'Phase 1': '#7a8ab8',  // Azul médio claro
      'Phase 2': '#9fabd0',  // Azul muito claro
      'Phase 3': '#d4c4a8',  // Dourado claro
      'Phase 4': '#baa898'   // Dourado médio claro
    }

    const backgroundColor = labels.map(label => colors[label])

    this.chart = new Chart(this.canvasTarget, {
      type: 'pie',
      data: {
        labels: labels,
        datasets: [{
          data: data,
          backgroundColor: backgroundColor,
          borderWidth: 2,
          borderColor: '#fff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        onClick: (event, elements) => {
          if (elements.length > 0) {
            const index = elements[0].index
            const phase = labels[index]
            this.filterByPhase(phase)
          }
        },
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              padding: 15,
              font: { size: 13 }
            }
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const label = context.label || ''
                const value = context.parsed
                const percent = percentages[context.dataIndex]
                return `${label}: ${value} casas (${percent})`
              }
            }
          }
        }
      }
    })
  }

  filterByPhase(phase) {
    // Construir URL com filtro
    const url = new URL(window.location.href)
    url.searchParams.set('phase', phase)

    // Navegar apenas o Turbo Frame da tabela
    window.Turbo.visit(url.toString(), { frame: "houses_table" })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
