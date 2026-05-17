import { LightningElement, track, wire } from "lwc";
import getMyQuotes from "@salesforce/apex/CkQuoteController.getMyQuotes";
import getQuoteDetail from "@salesforce/apex/CkQuoteController.getQuoteDetail";
import respondToQuote from "@salesforce/apex/CkQuoteController.respondToQuote";
import getQuotePdfUrl from "@salesforce/apex/CkPdfService.getQuotePdfUrl";
import { applyThemeToComponent } from "c/ckThemeUtils";

export default class CkMyQuotes extends LightningElement {
  @track quotes = [];
  @track isLoading = true;
  @track errorMessage = "";
  @track showModal = false;
  @track selectedQuote = null;
  @track isLoadingDetail = false;
  @track showConfirm = false;
  @track confirmAction = "";
  @track confirmQuoteId = "";
  @track isResponding = false;
  @track toast = "";
  @track toastType = "success";

  connectedCallback() {
    applyThemeToComponent(this);
  }

  @wire(getMyQuotes)
  wiredQuotes({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.quotes = data.map((q) => this.mapQuote(q));
    }
    if (error) {
      this.errorMessage = error.body
        ? error.body.message
        : "Failed to load quotes.";
    }
  }

  mapQuote(q) {
    return {
      ...q,
      grandTotal: q.grandTotal ? parseFloat(q.grandTotal).toFixed(2) : "0.00",
      discountPercent: q.discountPercent || 0,
      statusLabel: this.getStatusLabel(q.status),
      statusClass: this.getStatusClass(q.status),
      canRespond: q.status === "Sent to Customer"
    };
  }

  get isEmpty() {
    return !this.isLoading && this.quotes.length === 0 && !this.errorMessage;
  }
  get hasQuotes() {
    return !this.isLoading && this.quotes.length > 0;
  }

  getStatusLabel(status) {
    const map = {
      Draft: "📝 Draft",
      "Sent to Customer": "📨 Sent",
      Accepted: "✅ Accepted",
      Rejected: "❌ Rejected",
      Expired: "⏰ Expired"
    };
    return map[status] || status;
  }

  getStatusClass(status) {
    if (status === "Accepted") return "mq-status mq-status-accepted";
    if (status === "Sent to Customer") return "mq-status mq-status-sent";
    if (status === "Rejected") return "mq-status mq-status-rejected";
    if (status === "Expired") return "mq-status mq-status-expired";
    return "mq-status mq-status-draft";
  }

  // ── Detail Modal ─────────────────────────────────────────
  handleViewDetail(event) {
    const quoteId = event.currentTarget.dataset.id;
    this.showModal = true;
    this.isLoadingDetail = true;
    this.selectedQuote = { quoteName: "", quoteNumber: "" };

    getQuoteDetail({ quoteId })
      .then((data) => {
        this.isLoadingDetail = false;
        this.selectedQuote = {
          ...data,
          subtotal: data.subtotal
            ? parseFloat(data.subtotal).toFixed(2)
            : "0.00",
          grandTotal: data.grandTotal
            ? parseFloat(data.grandTotal).toFixed(2)
            : "0.00",
          tax: data.tax ? parseFloat(data.tax).toFixed(2) : "0.00",
          discountAmount: data.discountAmount
            ? parseFloat(data.discountAmount).toFixed(2)
            : "0.00",
          discountPercent: data.discountPercent || 0,
          statusLabel: this.getStatusLabel(data.status),
          statusClass: this.getStatusClass(data.status),
          canRespond: data.status === "Sent to Customer",
          items: data.items
            ? data.items.map((i) => ({
                ...i,
                unitPrice: i.unitPrice
                  ? parseFloat(i.unitPrice).toFixed(2)
                  : "0.00",
                totalPrice: i.totalPrice
                  ? parseFloat(i.totalPrice).toFixed(2)
                  : "0.00"
              }))
            : []
        };
      })
      .catch(() => {
        this.isLoadingDetail = false;
        this.errorMessage = "Failed to load quote details.";
      });
  }

  closeModal() {
    this.showModal = false;
    this.selectedQuote = null;
  }
  stopPropagation(event) {
    event.stopPropagation();
  }

  // ── Accept / Reject ──────────────────────────────────────
  handleAccept(event) {
    this.confirmQuoteId = event.currentTarget.dataset.id;
    this.confirmAction = "Accept";
    this.showConfirm = true;
  }

  handleReject(event) {
    this.confirmQuoteId = event.currentTarget.dataset.id;
    this.confirmAction = "Reject";
    this.showConfirm = true;
  }

  handleAcceptFromModal() {
    this.confirmQuoteId = this.selectedQuote.quoteId;
    this.confirmAction = "Accept";
    this.showConfirm = true;
  }

  handleRejectFromModal() {
    this.confirmQuoteId = this.selectedQuote.quoteId;
    this.confirmAction = "Reject";
    this.showConfirm = true;
  }

  get confirmTitle() {
    return this.confirmAction === "Accept" ? "Accept Quote?" : "Reject Quote?";
  }

  get confirmMessage() {
    return this.confirmAction === "Accept"
      ? "By accepting this quote, a contract will be created and our team will contact you shortly."
      : "Are you sure you want to reject this quote?";
  }

  get confirmBtnLabel() {
    return this.confirmAction === "Accept" ? "✓ Yes, Accept" : "✗ Yes, Reject";
  }

  get confirmBtnClass() {
    return this.confirmAction === "Accept" ? "mq-btn-accept" : "mq-btn-reject";
  }

  cancelConfirm() {
    this.showConfirm = false;
  }

  executeConfirm() {
    this.isResponding = true;

    respondToQuote({
      quoteId: this.confirmQuoteId,
      response: this.confirmAction
    })
      .then(() => {
        this.isResponding = false;
        this.showConfirm = false;
        this.showModal = false;

        // Refresh quotes
        this.quotes = this.quotes.map((q) => {
          if (q.quoteId === this.confirmQuoteId) {
            const newStatus =
              this.confirmAction === "Accept" ? "Accepted" : "Rejected";
            return {
              ...q,
              status: newStatus,
              statusLabel: this.getStatusLabel(newStatus),
              statusClass: this.getStatusClass(newStatus),
              canRespond: false
            };
          }
          return q;
        });

        this.showToast(
          this.confirmAction === "Accept"
            ? "✅ Quote accepted! Contract created."
            : "❌ Quote rejected.",
          this.confirmAction === "Accept" ? "success" : "error"
        );
      })
      .catch((error) => {
        this.isResponding = false;
        this.showConfirm = false;
        this.errorMessage = error.body
          ? error.body.message
          : "Failed to respond to quote.";
      });
  }

  // ── Download Quote PDF ───────────────────────────────────
  handleDownloadQuotePdf() {
    if (!this.selectedQuote) return;

    this.showToast("Preparing PDF...", "success");

    getQuotePdfUrl({ quoteId: this.selectedQuote.quoteId })
      .then((url) => {
        if (url) {
          window.open(url, "_blank");
        } else {
          this.showToast("Failed to generate PDF.", "error");
        }
      })
      .catch((error) => {
        const msg = error.body ? error.body.message : "Failed to download PDF.";
        this.showToast(msg, "error");
      });
  }

  // ── Toast ────────────────────────────────────────────────
  showToast(message, type) {
    this.toast = message;
    this.toastType = type;
    setTimeout(() => {
      this.toast = "";
    }, 4000);
  }

  get toastClass() {
    return this.toastType === "success"
      ? "mq-toast mq-toast-success"
      : "mq-toast mq-toast-error";
  }
}
