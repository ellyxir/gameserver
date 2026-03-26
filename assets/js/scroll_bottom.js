/**
 * LiveView hook that auto-scrolls a container to the bottom when new
 * content is added, but only if the user is already scrolled to the bottom.
 * If the user has scrolled up to read history, it stays put.
 */
const ScrollBottom = {
  mounted() {
    this._pinnedToBottom = true
    this.el.addEventListener("scroll", () => {
      const {scrollTop, scrollHeight, clientHeight} = this.el
      this._pinnedToBottom = scrollHeight - scrollTop - clientHeight < 16
    })
    this._scrollToBottom()
  },

  updated() {
    if (this._pinnedToBottom) {
      this._scrollToBottom()
    }
  },

  _scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
  }
}

export default ScrollBottom
