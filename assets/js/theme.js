// Theme persistence and toggle support.
// Reads/writes "phx:theme" in localStorage and sets the data-theme attribute.

function setTheme(theme) {
  if (theme === "system") {
    localStorage.removeItem("phx:theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("phx:theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
  }
}

// Apply saved theme immediately to avoid flash of wrong theme.
if (!document.documentElement.hasAttribute("data-theme")) {
  setTheme(localStorage.getItem("phx:theme") || "system")
}

// Sync theme across tabs via storage events.
window.addEventListener("storage", (e) => {
  if (e.key === "phx:theme") setTheme(e.newValue || "system")
})

// Handle theme toggle clicks dispatched from the LiveView component.
window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme))
