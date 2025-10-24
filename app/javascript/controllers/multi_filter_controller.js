import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="multi-filter"
export default class extends Controller {
  static targets = ["form", "columnSelect", "valueInput"]
  static values = { table: String }

  addFilter(event) {
    event.preventDefault()

    const column = this.columnSelectTarget.value
    const value = this.valueInputTarget.value.trim()

    if (!column || !value) {
      alert("Please select a column and enter a value")
      return
    }

    // Create hidden field for new filter
    const filterParam = this.tableValue === 'fmea' ? 'fmea_filters' : 'filters'
    const hiddenField = document.createElement('input')
    hiddenField.type = 'hidden'
    hiddenField.name = `${filterParam}[${column}]`
    hiddenField.value = value

    this.formTarget.appendChild(hiddenField)

    // Reset offset to 0 when adding new filter
    const offsetParam = this.tableValue === 'fmea' ? 'fmea_offset' : 'offset'
    let offsetField = this.formTarget.querySelector(`input[name="${offsetParam}"]`)
    if (!offsetField) {
      offsetField = document.createElement('input')
      offsetField.type = 'hidden'
      offsetField.name = offsetParam
      this.formTarget.appendChild(offsetField)
    }
    offsetField.value = '0'

    // Submit form
    this.formTarget.requestSubmit()

    // Reset form inputs for visual feedback
    this.columnSelectTarget.value = ''
    this.valueInputTarget.value = ''
  }
}
