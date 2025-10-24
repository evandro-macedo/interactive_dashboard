import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js/auto"

// Registrar todos os componentes do Chart.js
Chart.register(...registerables)

export default class extends Controller {
  static values = {
    summaryData: Array  // Query 11: open_scheduled_summary
  }

  static targets = ["canvas"]

  connect() {
    this.initChart()
  }

  initChart() {
    // Extrair dados da Query 11
    const labels = this.summaryDataValue.map(s => s.phase_atual)
    const data = this.summaryDataValue.map(s => parseInt(s.total_items_scheduled_abertos))
    const casas = this.summaryDataValue.map(s => parseInt(s.total_casas))
    const percentages = this.summaryDataValue.map(s => s.percentual)

    // Paleta CONSISTENTE: mesmas cores das badges (CSS variables)
    const colors = {
      'Phase 0': '#5b6b9f',  // Azul suave
      'Phase 1': '#7a8ab8',  // Azul médio claro
      'Phase 2': '#9fabd0',  // Azul muito claro
      'Phase 3': '#d4c4a8',  // Dourado claro
      'Phase 4': '#baa898'   // Dourado médio claro
    }

    const backgroundColor = labels.map(label => colors[label] || '#5a9fd6')

    this.chart = new Chart(this.canvasTarget, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Scheduled Abertos',
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
                const items = data[index]
                const houses = casas[index]
                const percent = percentages[index]
                return [
                  `${items} items scheduled`,
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
                size: 13
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
                size: 13,
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
    url.searchParams.set('phase_scheduled', phase)

    // Navegar apenas o Turbo Frame da tabela de scheduled abertos
    window.Turbo.visit(url.toString(), { frame: "open_scheduled_table" })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
