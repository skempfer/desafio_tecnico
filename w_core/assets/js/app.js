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
import {hooks as colocatedHooks} from "phoenix-colocated/w_core"
import topbar from "../vendor/topbar"

const ConnectionStatus = {
  mounted() {
    this.updateState(this.liveSocket.isConnected() ? "connected" : "disconnected")

    this.handleConnected = () => this.updateState("connected")
    this.handleDisconnected = () => this.updateState("disconnected")

    window.addEventListener("phx:connected", this.handleConnected)
    window.addEventListener("phx:disconnected", this.handleDisconnected)
  },

  destroyed() {
    window.removeEventListener("phx:connected", this.handleConnected)
    window.removeEventListener("phx:disconnected", this.handleDisconnected)
  },

  updateState(state) {
    this.el.dataset.state = state

    const label = this.el.querySelector("[data-role='connection-label']")
    if (label) {
      label.textContent = state === "connected" ? "Live" : "Reconnecting"
    }
  },
}

const DashboardLoading = {
  mounted() {
    this.activeLoads = 0

    this.onStart = () => {
      this.activeLoads += 1
      this.setLoading(true)
    }

    this.onStop = () => {
      this.activeLoads = Math.max(0, this.activeLoads - 1)

      if (this.activeLoads === 0) {
        this.setLoading(false)
      }
    }

    window.addEventListener("phx:page-loading-start", this.onStart)
    window.addEventListener("phx:page-loading-stop", this.onStop)
  },

  destroyed() {
    window.removeEventListener("phx:page-loading-start", this.onStart)
    window.removeEventListener("phx:page-loading-stop", this.onStop)
  },

  setLoading(isLoading) {
    this.el.dataset.loading = isLoading ? "true" : "false"
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ConnectionStatus, DashboardLoading},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

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
