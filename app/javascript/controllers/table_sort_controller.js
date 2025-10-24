import { Controller } from "@hotwired/stimulus"

/**
 * Table Sort Controller
 *
 * Adiciona funcionalidade de ordenação clicável para tabelas HTML.
 * Suporta ordenação de números, datas e strings.
 *
 * Uso:
 * <table data-controller="table-sort" data-table-sort-target="table">
 *   <thead>
 *     <tr>
 *       <th data-action="click->table-sort#sort" class="sortable">Coluna</th>
 *     </tr>
 *   </thead>
 * </table>
 */
export default class extends Controller {
  static targets = ["table"]

  connect() {
    this.sortColumn = null
    this.sortDirection = 'asc'
  }

  sort(event) {
    const th = event.currentTarget
    const columnIndex = Array.from(th.parentElement.children).indexOf(th)
    const tbody = this.tableTarget.querySelector('tbody')
    const rows = Array.from(tbody.querySelectorAll('tr'))

    // Toggle direction if clicking same column
    if (this.sortColumn === columnIndex) {
      this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc'
    } else {
      this.sortDirection = 'asc'
    }
    this.sortColumn = columnIndex

    // Sort rows
    rows.sort((a, b) => {
      const aCell = a.children[columnIndex]
      const bCell = b.children[columnIndex]

      if (!aCell || !bCell) return 0

      const aText = aCell.textContent.trim()
      const bText = bCell.textContent.trim()

      // Parse values (detect type and compare)
      const aValue = this.parseValue(aText)
      const bValue = this.parseValue(bText)

      let comparison = 0
      if (aValue > bValue) {
        comparison = 1
      } else if (aValue < bValue) {
        comparison = -1
      }

      return this.sortDirection === 'asc' ? comparison : -comparison
    })

    // Reattach sorted rows
    rows.forEach(row => tbody.appendChild(row))

    // Update visual indicators
    this.updateIndicators(th)
  }

  parseValue(text) {
    // Remove HTML tags (badges, etc)
    const cleanText = text.replace(/<[^>]*>/g, '').trim()

    // Empty values go to bottom
    if (cleanText === '' || cleanText === '-') {
      return this.sortDirection === 'asc' ? '\uFFFF' : ''
    }

    // Try to parse as number first
    const numMatch = cleanText.match(/^-?[\d,]+\.?\d*/)
    if (numMatch) {
      const num = parseFloat(numMatch[0].replace(/,/g, ''))
      if (!isNaN(num)) return num
    }

    // Try to parse as date (MM/DD format or ISO)
    if (cleanText.match(/^\d{1,2}\/\d{1,2}/) || cleanText.match(/^\d{4}-\d{2}-\d{2}/)) {
      const date = new Date(cleanText)
      if (!isNaN(date.getTime())) return date.getTime()
    }

    // Return as lowercase string for case-insensitive comparison
    return cleanText.toLowerCase()
  }

  updateIndicators(currentTh) {
    // Remove all indicators from headers
    this.tableTarget.querySelectorAll('th.sortable').forEach(th => {
      th.classList.remove('sorted-asc', 'sorted-desc')
    })

    // Add indicator to current column
    currentTh.classList.add(`sorted-${this.sortDirection}`)
  }
}
