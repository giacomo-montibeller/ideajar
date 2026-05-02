// Slice 7b step 5 — Geolocation hook.
//
// Mounted on the "Usa la mia posizione" button in the distance filter
// sub-block. On click we ask the browser for the current position and
// pushEvent the result (or a denial reason) to the LiveView. Server-
// side handlers `set_user_location` and `user_location_denied` (slice
// 7b step 6) take it from there.
//
// Design notes:
//
//   * The click listener is registered ONLY in `mounted()`. Phoenix LV
//     calls the update callback on every diff, and stacking another
//     `addEventListener` per patch would produce N pushEvents per
//     click. There is no per-update callback in this hook by design.
//   * W3C PositionError codes are mapped to four documented reason
//     strings the server understands: "permission_denied" (1),
//     "unavailable" (2), "timeout" (3), "unsupported" (no API). The
//     server then translates these to canonical IT flash strings.
//   * No retry logic, no state machine, no permission persistence.
//     Failure surfaces a flash and the user can click again.

export const Geolocation = {
  mounted() {
    this.el.addEventListener("click", () => {
      if (!navigator.geolocation) {
        this.pushEvent("user_location_denied", { reason: "unsupported" })
        return
      }

      navigator.geolocation.getCurrentPosition(
        (pos) => this.pushEvent("set_user_location", {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude
        }),
        (err) => {
          // W3C PositionError: 1=PERMISSION_DENIED, 2=POSITION_UNAVAILABLE, 3=TIMEOUT.
          const reason =
            err.code === 1 ? "permission_denied" :
            err.code === 2 ? "unavailable" :
            err.code === 3 ? "timeout" : "unsupported"
          this.pushEvent("user_location_denied", { reason })
        }
      )
    })
  }
}
