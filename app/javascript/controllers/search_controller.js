import { Controller } from "@hotwired/stimulus"

// Real-time search controller with debounce
// Connects to data-controller="search"
export default class extends Controller {
  static targets = ["form"]

  connect() {
    this.timeout = null
  }

  disconnect() {
    // Cleanup pattern from lessons-learned
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  search() {
    // Clear existing timeout
    clearTimeout(this.timeout)

    // Debounce 300ms to avoid overwhelming the database
    this.timeout = setTimeout(() => {
      this.formTarget.requestSubmit()
    }, 300)
  }
}
