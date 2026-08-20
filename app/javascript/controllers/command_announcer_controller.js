// SPDX-License-Identifier: AGPL-3.0-or-later
import { Controller } from "@hotwired/stimulus"

// [UI.3] SR-анонс термінальних станів команд актуатора (присуд 2026-08-20:
// лише confirmed/failed, polite — проміжні мовчать, інакше батч на 20 рядків
// дає шквал анонсів). Регіон живе поза turbo-фреймами й переживає їх заміну;
// подія — turbo:frame-load заглушки зі `src` (class-2 pull), тобто анонс іде
// рівно тоді, коли клієнт сам дотягнув свіжий стан у власній локалі.
export default class extends Controller {
  static targets = ["region"]
  static values = { messages: Object, terminal: Array }

  announce(event) {
    const badge = event.target.querySelector("[data-command-state]")
    if (!badge) return

    const state = badge.dataset.commandState
    if (!this.terminalValue.includes(state)) return

    const template = this.messagesValue[state]
    if (!template) return

    const id = event.target.id.replace("command_status_frame_", "")
    this.regionTarget.textContent = template.replace("%{id}", id)
  }
}
