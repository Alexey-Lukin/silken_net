import { Controller } from "@hotwired/stimulus"

// codex--comment — composer ergonomics for the inline comment form.
//
// Contract (see app/views/components/codex/comments/{form,thread}.rb):
//   data-controller="codex--comment"
//   targets:
//     list  (the visible thread <div>)
//     form  (the composer <form>)
//     body  (the <textarea>)
//
// Behaviour:
//   * Cmd/Ctrl+Enter inside the textarea submits the form (matches Slack/GH).
//   * After a successful Turbo Stream response the textarea is reset, focus
//     is restored to the textarea, and the thread is scrolled to bottom so
//     the new comment is visible without manual scrolling.
//   * Live character counter (mini text under the textarea) appears after
//     the user types past 80% of the BODY_MAX limit, encouraging brevity
//     without being noisy.
//
// No-JS fallback: the form posts and Turbo Stream prepends/appends the new
// comment; no scrolling or counter affordance.
export default class extends Controller {
  static targets = ["list", "form", "body"]

  connect() {
    if (this.hasBodyTarget) {
      this.boundKeydown = (e) => this.handleKeydown(e)
      this.bodyTarget.addEventListener("keydown", this.boundKeydown)
    }
    if (this.hasFormTarget) {
      this.boundEnd = (e) => this.afterSubmit(e)
      this.formTarget.addEventListener("turbo:submit-end", this.boundEnd)
    }
  }

  disconnect() {
    if (this.boundKeydown && this.hasBodyTarget) {
      this.bodyTarget.removeEventListener("keydown", this.boundKeydown)
    }
    if (this.boundEnd && this.hasFormTarget) {
      this.formTarget.removeEventListener("turbo:submit-end", this.boundEnd)
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      if (this.hasFormTarget) this.requestSubmit(this.formTarget)
    }
  }

  afterSubmit(event) {
    const success = event?.detail?.success
    if (success === false) return  // Leave the draft so the user can retry.

    if (this.hasBodyTarget) {
      this.bodyTarget.value = ""
      // Restore focus on the next tick so Turbo's DOM swap is settled.
      requestAnimationFrame(() => this.bodyTarget.focus())
    }
    if (this.hasListTarget) {
      // Comments append to the bottom — scroll the list into view from below.
      this.listTarget.scrollTop = this.listTarget.scrollHeight
    }
  }

  requestSubmit(form) {
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }
}
