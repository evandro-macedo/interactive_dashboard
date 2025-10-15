import { Controller } from "@hotwired/stimulus"

// Preserves horizontal scroll position when Turbo Frame updates table
// Connects to data-controller="table-scroll"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    // Listen for Turbo Frame render events to preserve scroll position
    this.boundBeforeRender = this.beforeRender.bind(this)
    this.boundAfterRender = this.afterRender.bind(this)

    document.addEventListener("turbo:before-frame-render", this.boundBeforeRender)
    document.addEventListener("turbo:frame-render", this.boundAfterRender)
  }

  disconnect() {
    // Cleanup pattern from lessons-learned
    document.removeEventListener("turbo:before-frame-render", this.boundBeforeRender)
    document.removeEventListener("turbo:frame-render", this.boundAfterRender)
  }

  beforeRender(event) {
    // Only handle events for the dailylogs_table frame
    if (event.detail?.newFrame?.id === "dailylogs_table") {
      // Save current scroll position before Turbo replaces content
      if (this.hasContainerTarget) {
        this.savedScrollLeft = this.containerTarget.scrollLeft
        this.savedScrollTop = this.containerTarget.scrollTop
      }
    }
  }

  afterRender(event) {
    // Only handle events for the dailylogs_table frame
    if (event.detail?.fetchResponse?.response?.url?.includes("dailylogs")) {
      // Restore scroll position after Turbo has rendered new content
      // Use requestAnimationFrame to ensure DOM is fully updated
      requestAnimationFrame(() => {
        if (this.hasContainerTarget && this.savedScrollLeft !== undefined) {
          this.containerTarget.scrollLeft = this.savedScrollLeft
          this.containerTarget.scrollTop = this.savedScrollTop
        }
      })
    }
  }
}
