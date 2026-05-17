import { LightningElement, api } from "lwc";
import submitProductReview from "@salesforce/apex/CkReviewController.submitProductReview";

export default class CkWriteProductReview extends LightningElement {
  @api productId;
  @api productName;

  rating = 0;
  hoverRating = 0;
  title = "";
  comment = "";
  recommended = null; // true / false / null

  isSubmitting = false;
  errorMessage = "";

  // ─── Computed ─────────────────────────────────
  get starsToRender() {
    return [1, 2, 3, 4, 5].map((i) => ({
      id: i,
      value: i,
      cssClass: this.getStarClass(i)
    }));
  }

  getStarClass(starValue) {
    const displayRating = this.hoverRating || this.rating;
    return starValue <= displayRating ? "wpr-star wpr-star-active" : "wpr-star";
  }

  get ratingText() {
    if (this.rating === 0) return "Click to rate";
    const texts = ["", "Poor", "Fair", "Good", "Very Good", "Excellent"];
    return texts[this.rating];
  }

  get recommendYesClass() {
    return this.recommended === true
      ? "wpr-rec-btn wpr-rec-btn-active wpr-rec-btn-yes"
      : "wpr-rec-btn";
  }

  get recommendNoClass() {
    return this.recommended === false
      ? "wpr-rec-btn wpr-rec-btn-active wpr-rec-btn-no"
      : "wpr-rec-btn";
  }

  get submitButtonLabel() {
    return this.isSubmitting ? "Submitting..." : "Submit Review";
  }

  get titleCharCount() {
    return `${this.title.length}/80`;
  }

  get commentCharCount() {
    return `${this.comment.length}/2000`;
  }

  get canSubmit() {
    return (
      this.rating > 0 &&
      this.title.trim().length > 0 &&
      this.comment.trim().length > 10 &&
      this.recommended !== null &&
      !this.isSubmitting
    );
  }

  get submitBtnClass() {
    return this.canSubmit
      ? "wpr-btn-submit"
      : "wpr-btn-submit wpr-btn-submit-disabled";
  }

  // ─── Handlers ─────────────────────────────────
  handleStarClick(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10);
    this.rating = value;
  }

  handleStarHover(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10);
    this.hoverRating = value;
  }

  handleStarLeave() {
    this.hoverRating = 0;
  }

  handleTitleChange(event) {
    const val = event.target.value;
    this.title = val.length > 80 ? val.substring(0, 80) : val;
  }

  handleCommentChange(event) {
    const val = event.target.value;
    this.comment = val.length > 2000 ? val.substring(0, 2000) : val;
  }

  handleRecommendYes() {
    this.recommended = true;
  }

  handleRecommendNo() {
    this.recommended = false;
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleOverlayClick(event) {
    if (event.target.classList.contains("wpr-overlay")) {
      this.handleClose();
    }
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  async handleSubmit() {
    if (!this.canSubmit) return;

    this.errorMessage = "";
    this.isSubmitting = true;

    try {
      await submitProductReview({
        productId: this.productId,
        rating: this.rating,
        title: this.title.trim(),
        comment: this.comment.trim(),
        recommended: this.recommended
      });

      this.isSubmitting = false;
      this.dispatchEvent(new CustomEvent("submitted"));
    } catch (error) {
      this.isSubmitting = false;
      this.errorMessage = error.body
        ? error.body.message
        : "Failed to submit review. Please try again.";
    }
  }
}
