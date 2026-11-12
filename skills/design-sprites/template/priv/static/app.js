import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// DraftFlush: the pagehide safety net. When the page is hidden or closed,
// beacon the form's current values to POST /api/draft, which runs the
// same normalized, idempotent server-side save as the socket path — so
// the last edits inside the debounce window survive the socket dying.
// FormData carries the form's _csrf_token field.
const DraftFlush = {
  mounted() {
    this.flush = () => {
      const data = new FormData(this.el);
      navigator.sendBeacon("/api/draft", data);
    };
    this.onVisibility = () => {
      if (document.visibilityState === "hidden") this.flush();
    };
    document.addEventListener("visibilitychange", this.onVisibility);
    window.addEventListener("pagehide", this.flush);
  },
  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility);
    window.removeEventListener("pagehide", this.flush);
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  // Sprite edge + mobile Safari kill long-lived websockets (~1-2 min in
  // soak tests); fall back to the endpoint's longpoll transport instead
  // of opening a silent-save window.
  longPollFallbackMs: 2500,
  hooks: { DraftFlush },
});

liveSocket.connect();
window.liveSocket = liveSocket;
