// LeafletMap hook — minimal click-picker for the location dialog.
//
// WAI-ARIA APG note (slice 7a, A1-A6): the surrounding HTML5 <dialog>
// supplies the role="dialog" semantics, focus trap, backdrop, and
// Esc-to-close natively. This hook stays UI-pure: it boots Leaflet,
// wires a single click handler, and forwards the lat/lng to the
// LiveView. No focus management, no a11y wiring, no state.
//
// Why window.L (not ES import): the vendored leaflet.js (1.9.4) is the
// official UMD bundle. Esbuild detects the CommonJS branch first and
// stashes the API on `exports.leaflet`, so a bare `import L from
// "../vendor/leaflet"` does NOT yield the global Leaflet API. Loading
// leaflet.js via a <script> tag in root.html.heex (before app.js) lets
// the UMD bundle take its `window.L = t` branch — the documented
// fallback path used by every Phoenix-without-npm app shipping
// Leaflet. This is the project's "minimize JS" constraint expressed
// in vendoring terms (CC4 + CC9 of the slice 7a plan).
//
// CC20 — `tap: false`: disables Leaflet's iOS tap-emulation layer.
// On modern iOS Safari (17+) the emulation introduces a perceptible
// click delay and occasionally drops touches; the native click events
// are accurate enough for our pin-precision needs.
//
// CC21 — defaults: center [43.5, 12.5] (peninsular Italy centroid,
// excluding the islands so Sicily/Sardinia don't pull the centroid
// south) at zoom level 6 (regional-level view). Both are read from
// the host element's `data-default-center` / `data-default-zoom`
// attributes so the template stays the single source of truth.
//
// Server-side reverse geocoding: this hook only forwards click coords;
// the LiveView handler calls `Ideajar.Geocoding.reverse_lookup/2` and
// emits `phx:close-dialog` to dismiss the dialog when done. That flow
// is wired in slice 7a step 7; step 6 (this hook) only ships the
// shell.
export const LeafletMap = {
  mounted() {
    const L = window.L

    if (!L) {
      // Surfaced loud-and-clear so an asset regression (missing
      // <script> tag in root.html.heex, or vendor file not mirrored
      // into priv/static/assets/vendor/) doesn't degrade silently
      // into a blank dialog body.
      console.error(
        "Leaflet not loaded — check the <script src=\"/assets/vendor/leaflet.js\"> tag in root.html.heex and that mix assets.build mirrored the vendor file under priv/static."
      )
      return
    }

    const center = JSON.parse(this.el.dataset.defaultCenter || "[43.5, 12.5]")
    const zoom = parseInt(this.el.dataset.defaultZoom || "6", 10)

    this.map = L.map(this.el, { tap: false }).setView(center, zoom)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "© OpenStreetMap",
    }).addTo(this.map)

    this.map.on("click", (e) => {
      this.pushEvent("set_location", { lat: e.latlng.lat, lng: e.latlng.lng })
    })
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  },
}
