import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js/auto"

// Registrar todos os componentes do Chart.js
Chart.register(...registerables)

export default class extends Controller {
  static values = {
    summaryData: Array  // Query 7: failed_inspections_summary
  }

  static targets = ["canvas"]

  connect() {
    this.initChart()
  }

  initChart() {
    // Extrair dados da Query 7
    const labels = this.summaryDataValue.map(s => s.phase_atual)
    const data = this.summaryDataValue.map(s => parseInt(s.total_inspections_reprovadas))
    const casas = this.summaryDataValue.map(s => parseInt(s.total_casas))
    const percentages = this.summaryDataValue.map(s => s.percentual)

    // Cores SB Admin 2 por phase
    const colors = {
      'Phase 0': '#4e73df',  // Primary (azul)
      'Phase 1': '#1cc88a',  // Success (verde)
      'Phase 2': '#36b9cc',  // Info (ciano)
      'Phase 3': '#f6c23e',  // Warning (amarelo)
      'Phase 4': '#e74a3b'   // Danger (vermelho)
    }

    const backgroundColor = labels.map(label => colors[label] || '#858796')

    this.chart = new Chart(this.canvasTarget, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Inspeções Reprovadas',
          data: data,
          backgroundColor: backgroundColor,
          borderColor: backgroundColor,
          borderWidth: 1
        }]
      },
      options: {
        indexAxis: 'y',  // Barras horizontais
        responsive: true,
        maintainAspectRatio: false,
        onClick: (event, elements) => {
          if (elements.length > 0) {
            const index = elements[0].index
            const phase = labels[index]
            this.filterByPhase(phase)
          }
        },
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const index = context.dataIndex
                const inspections = data[index]
                const houses = casas[index]
                const percent = percentages[index]
                return [
                  `${inspections} inspeções`,
                  `${houses} casas (${percent})`
                ]
              }
            }
          }
        },
        scales: {
          x: {
            beginAtZero: true,
            ticks: {
              precision: 0,
              font: {
                size: 11
              }
            },
            grid: {
              display: true,
              drawBorder: false
            }
          },
          y: {
            ticks: {
              font: {
                size: 12,
                weight: 'bold'
              }
            },
            grid: {
              display: false
            }
          }
        }
      }
    })
  }

  filterByPhase(phase) {
    // Construir URL com filtro
    const url = new URL(window.location.href)
    url.searchParams.set('phase_inspections', phase)

    // Navegar apenas o Turbo Frame da tabela de inspeções
    window.Turbo.visit(url.toString(), { frame: "failed_inspections_table" })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
