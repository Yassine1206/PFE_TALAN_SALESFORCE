import { LightningElement, api, wire, track } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getProductReviewSummary from "@salesforce/apex/CkReviewController.getProductReviewSummary";

export default class CkProductReviews extends LightningElement {
  @api productId;
  @api productName;

  @track summary = null;
  @track isLoading = true;
  @track showWriteModal = false;

  _wiredResult;

  @wire(getProductReviewSummary, { productId: "$productId" })
  wiredSummary(result) {
    this._wiredResult = result;
    if (result.data) {
      this.summary = result.data;
      this.isLoading = false;
    } else if (result.error) {
      console.error("Error loading reviews:", result.error);
      this.isLoading = false;
    }
  }

  renderedCallback() {
    // Apply bar widths via DOM after render
    if (this.summary && this.summary.breakdown) {
      const bars = this.template.querySelectorAll(".rev-bar-fill");
      bars.forEach((bar, idx) => {
        const breakdown = this.summary.breakdown[idx];
        if (breakdown) {
          bar.style.width = breakdown.percentage + "%";
        }
      });
    }
  }

  // ─── Computed properties ─────────────────────────
  get hasReviews() {
    return this.summary && this.summary.reviewCount > 0;
  }

  get hasNoReviews() {
    return (
      this.summary &&
      (!this.summary.reviewCount || this.summary.reviewCount === 0)
    );
  }

  get averageRatingFormatted() {
    return this.summary && this.summary.averageRating
      ? Number(this.summary.averageRating).toFixed(1)
      : "0.0";
  }

  get reviewCountText() {
    if (!this.summary) return "";
    const count = this.summary.reviewCount;
    return count === 1 ? "1 review" : `${count} reviews`;
  }

  get showRecommended() {
    return (
      this.summary &&
      this.summary.recommendedPercent !== null &&
      this.summary.recommendedPercent !== undefined
    );
  }

  get averageStarsArray() {
    if (!this.summary || !this.summary.averageRating) {
      return [
        { id: 1, cssClass: "rev-star" },
        { id: 2, cssClass: "rev-star" },
        { id: 3, cssClass: "rev-star" },
        { id: 4, cssClass: "rev-star" },
        { id: 5, cssClass: "rev-star" }
      ];
    }
    const rating = Math.round(this.summary.averageRating);
    return [1, 2, 3, 4, 5].map((i) => ({
      id: i,
      cssClass: i <= rating ? "rev-star rev-star-filled" : "rev-star"
    }));
  }

  get reviewsWithComputedFields() {
    if (!this.summary || !this.summary.reviews) return [];
    return this.summary.reviews.map((r) => ({
      ...r,
      badgeClass:
        r.customerType === "B2B"
          ? "rev-badge rev-badge-b2b"
          : "rev-badge rev-badge-b2c",
      starsComputed: (r.starsArray || []).map((s, idx) => ({
        key: "star-" + r.id + "-" + idx,
        cssClass: s === 1 ? "rev-star rev-star-filled" : "rev-star"
      }))
    }));
  }

  // ─── Handlers ────────────────────────────────────
  handleOpenWriteModal() {
    this.showWriteModal = true;
  }

  handleCloseModal() {
    this.showWriteModal = false;
  }

  handleReviewSubmitted() {
    this.showWriteModal = false;
    refreshApex(this._wiredResult);
  }
}
