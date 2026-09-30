// Loaded by PhoenixStorybook before its own JS. Declare LiveView hooks, params
// and uploaders that your components need on `window.storybook`.
(function () {
  const Hooks = {}

  // Renders the diagram source in the element's text with mermaid, loaded lazily from a CDN.
  Hooks.Mermaid = {
    mounted() {
      this.source = this.el.textContent
      this.render()
    },
    async render() {
      const {default: mermaid} = await import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs")
      // Storybook's page is always light, so never follow the OS dark preference.
      mermaid.initialize({
        startOnLoad: false,
        theme: "default",
        themeVariables: {fontSize: "18px"},
        flowchart: {useMaxWidth: false, htmlLabels: true, nodeSpacing: 40, rankSpacing: 50},
      })
      const {svg} = await mermaid.render(`${this.el.id}-svg`, this.source)
      this.el.innerHTML = svg
    },
  }

  window.storybook = {Hooks}
})()
