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

    // Cores SB Admin 2 por phase
    const colors = {
      'Phase 0': '#4e73df',  // Primary (azul)
      'Phase 1': '#1cc88a',  // Success (verde)
      'Phase 2': '#36b9cc',  // Info (ciano)
      'Phase 3': '#f6c23e',  // Warning (amarelo)
      'Phase 4': '#e74a3b'   // Danger (vermelho)
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
              font: { size: 12 }
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
