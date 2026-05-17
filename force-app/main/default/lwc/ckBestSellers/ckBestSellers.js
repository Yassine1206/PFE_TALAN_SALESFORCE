import { LightningElement, track, wire } from "lwc";
import getBestSellers from "@salesforce/apex/CkProductController.getBestSellers";

export default class CkBestSellers extends LightningElement {
  @track products = [];
  @track isLoading = true;
  _autoScrollTimer;
  _isDragging = false;
  _startX = 0;
  _scrollLeft = 0;

  @wire(getBestSellers, { maxProducts: 10 })
  wiredProducts({ data, error }) {
    if (data) {
      const mapped = data.map((p, idx) => ({
        ...p,
        uniqueKey: "orig-" + p.id, // Clé unique pour template
        priceNum:
          p.priceNum != null
            ? Number(p.priceNum)
            : p.price
              ? Number(String(p.price).replace("$", "").trim())
              : 0,
        detailUrl: "/s/product-detail?productId=" + p.id,
        soldText: (p.totalSold || 0) + " sold"
      }));

      // ⭐ Duplicate for infinite loop effect
      const duplicated = data.map((p, idx) => ({
        ...p,
        uniqueKey: "dup-" + p.id, // Clé différente pour les doublons
        priceNum:
          p.priceNum != null
            ? Number(p.priceNum)
            : p.price
              ? Number(String(p.price).replace("$", "").trim())
              : 0,
        detailUrl: "/s/product-detail?productId=" + p.id,
        soldText: (p.totalSold || 0) + " sold"
      }));

      this.products = [...mapped, ...duplicated];
      this.isLoading = false;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => this.startAutoScroll(), 500);
    } else if (error) {
      this.isLoading = false;
    }
  }

  disconnectedCallback() {
    clearInterval(this._autoScrollTimer);
  }

  startAutoScroll() {
    const trackEl = this.template.querySelector(".bs-track");
    if (!trackEl) return;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._autoScrollTimer = setInterval(() => {
      if (this._isDragging) return;

      trackEl.scrollLeft += 1;

      // ⭐ Seamless reset : when we reach the halfway point (end of original list),
      // jump back to scrollLeft = 0. Since the dup list looks identical at that position,
      // the user sees no jump.
      const halfWidth = trackEl.scrollWidth / 2;
      if (trackEl.scrollLeft >= halfWidth) {
        // Disable smooth scroll temporarily for instant reset
        const previousBehavior = trackEl.style.scrollBehavior;
        trackEl.style.scrollBehavior = "auto";
        trackEl.scrollLeft = 0;
        trackEl.style.scrollBehavior = previousBehavior;
      }
    }, 30);
  }

  handleMouseDown(event) {
    const trackEl = this.template.querySelector(".bs-track");
    this._isDragging = true;
    this._startX = event.pageX - trackEl.offsetLeft;
    this._scrollLeft = trackEl.scrollLeft;
    trackEl.classList.add("bs-track-grabbing");
  }

  handleMouseMove(event) {
    if (!this._isDragging) return;
    event.preventDefault();
    const trackEl = this.template.querySelector(".bs-track");
    const x = event.pageX - trackEl.offsetLeft;
    const walk = (x - this._startX) * 2;
    trackEl.scrollLeft = this._scrollLeft - walk;
  }

  handleMouseUp() {
    this._isDragging = false;
    const trackEl = this.template.querySelector(".bs-track");
    if (trackEl) trackEl.classList.remove("bs-track-grabbing");
  }

  handleMouseLeave() {
    this._isDragging = false;
    const trackEl = this.template.querySelector(".bs-track");
    if (trackEl) trackEl.classList.remove("bs-track-grabbing");
  }

  get hasProducts() {
    return this.products.length > 0;
  }

  // handleQuickAdd supprimé — ckProductCard dispatche directement sur window
}
