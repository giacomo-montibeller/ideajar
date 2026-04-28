// RovingTabindex hook — keyboard navigation for chip groups.
//
// Implements the WAI-ARIA APG "roving tabindex" pattern
// (https://www.w3.org/WAI/ARIA/apg/patterns/keyboard-interface/) for a
// horizontal group of focusable buttons (e.g. the filter row category
// chips). The group is mounted with exactly one child carrying
// tabindex="0" and the rest tabindex="-1" — this collapses the chip
// group to a single Tab stop. ArrowLeft/ArrowRight cycle focus within
// the group with wrap-around; Home/End jump to the first/last chip.
//
// Server invariant (initial tabindex distribution + presence of the
// phx-hook attribute on the role=group wrapper) is verified in
// `test/ideajar_web/live/idea_live/index_test.exs`. Arrow-key behaviour
// is JS — the LV test pipeline does not execute hook callbacks — and is
// covered by V1b manual verification.
//
// LV reconnect note (R5-15): on a reconnect the server re-emits the
// initial distribution (tabindex="0" on the first chip), so client-side
// focus index is reset to 0. If the user was cycling chip 5/8 at the
// time of a network blip, focus jumps back to the first chip. This is
// the documented trade-off; the trigger to revisit it is an SR-user
// complaint about lost focus during prolonged use.
export const RovingTabindex = {
  mounted() {
    this._handler = (e) => this.onKey(e)
    this.el.addEventListener("keydown", this._handler)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this._handler)
  },
  onKey(e) {
    if (
      e.key !== "ArrowRight" &&
      e.key !== "ArrowLeft" &&
      e.key !== "Home" &&
      e.key !== "End"
    ) {
      return
    }
    const buttons = Array.from(this.el.querySelectorAll("button"))
    if (buttons.length === 0) return
    const currentIdx = buttons.findIndex((b) => b === document.activeElement)
    if (currentIdx === -1) return
    e.preventDefault()
    let nextIdx
    if (e.key === "ArrowRight") {
      nextIdx = (currentIdx + 1) % buttons.length
    } else if (e.key === "ArrowLeft") {
      nextIdx = (currentIdx - 1 + buttons.length) % buttons.length
    } else if (e.key === "Home") {
      nextIdx = 0
    } else {
      nextIdx = buttons.length - 1
    }
    buttons.forEach((b, i) =>
      b.setAttribute("tabindex", i === nextIdx ? "0" : "-1")
    )
    buttons[nextIdx].focus()
  },
}
