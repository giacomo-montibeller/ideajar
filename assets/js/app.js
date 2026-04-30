// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ideajar"
import {RovingTabindex} from "./hooks/roving_tabindex"
import {LeafletMap} from "./hooks/leaflet_map"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, RovingTabindex, LeafletMap},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Move focus when the LiveView asks us to. The server emits
// `push_event("ideajar:focus", %{to: "#some-id"})` and we deliver the focus
// here, so the behaviour is testable from the server side and survives
// re-renders that would defeat the HTML `autofocus` attribute.
window.addEventListener("phx:ideajar:focus", e => {
  const target = e.detail && e.detail.to
  if (!target) return
  const node = document.querySelector(target)
  if (node) node.focus()
})

// Slice 7a — bridge HTML5 <dialog> open/close to native methods. Used by:
//   * server push_event("phx:close-dialog", %{id: "..."}) from post-handler
//     code (e.g. after a successful set_location reverse geocode);
//   * client JS.dispatch from button phx-click (Apri mappa / Chiudi). The
//     event bubbles to window from the button; we resolve the dialog by
//     `detail.id` so both server and client paths share the same listener.
//
// Phoenix.LiveView.JS does not expose a primitive that calls element DOM
// methods like showModal()/close() directly (JS.exec is for command attrs,
// not method invocation), so this small bridge is the documented pattern.
window.addEventListener("phx:open-dialog", e => {
  const id = e.detail && e.detail.id
  if (!id) return
  const dialog = document.getElementById(id)
  if (!dialog || typeof dialog.showModal !== "function") return
  dialog.showModal()
  // Dismiss paths: explicit close button (✕) and Esc key (HTML5 native).
  // The LeafletMap hook's ResizeObserver auto-invalidates the map size
  // once the container takes real dimensions, so no extra wiring here.
})

window.addEventListener("phx:close-dialog", e => {
  const id = e.detail && e.detail.id
  if (!id) return
  const dialog = document.getElementById(id)
  if (dialog && typeof dialog.close === "function") dialog.close()
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

