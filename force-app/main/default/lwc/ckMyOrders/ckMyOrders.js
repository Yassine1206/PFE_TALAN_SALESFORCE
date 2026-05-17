import { LightningElement, track, wire } from "lwc";
import getMyOrders from "@salesforce/apex/CkOrderController.getMyOrders";
import getOrderDetail from "@salesforce/apex/CkOrderController.getOrderDetail";
import addToCart from "@salesforce/apex/CkCartController.addToCart";
import { NavigationMixin } from "lightning/navigation";
import getInvoicePdfUrl from "@salesforce/apex/CkPdfService.getInvoicePdfUrl";

const PAGE_SIZE = 6; // 3 colonnes × 2 lignes

export default class CkMyOrders extends NavigationMixin(LightningElement) {
  @track allOrders = [];
  @track filteredOrders = [];
  @track isLoading = true;
  @track errorMessage = "";
  @track showModal = false;
  @track selectedOrder = null;
  @track isLoadingDetail = false;
  @track showReorderToast = false;
  @track currentPage = 1;

  // FIX : variables @track liées aux selects → reset automatique
  @track searchTerm = "";
  @track statusFilter = "";
  @track paymentFilter = "";
  @track sortOrder = "date-desc";

  @wire(getMyOrders)
  wiredOrders({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.allOrders = data.map((o) => this.mapOrder(o));
      this.applyFilters();
    }
    if (error) {
      this.errorMessage = error.body
        ? error.body.message
        : "Error loading orders.";
    }
  }

  mapOrder(o) {
    return {
      ...o,
      totalTTC: o.totalTTC ? parseFloat(o.totalTTC).toFixed(2) : "0.00",
      statusLabel: this.getStatusLabel(o.status),
      statusClass: this.getStatusClass(o.status)
    };
  }

  // ── Counts ───────────────────────────────────────────────
  get totalCount() {
    return this.allOrders.length;
  }
  get filteredCount() {
    return this.filteredOrders.length;
  }
  get paidCount() {
    return this.allOrders.filter((o) => o.status === "Paid").length;
  }
  get codCount() {
    return this.allOrders.filter(
      (o) => o.status === "Awaiting Delivery Payment"
    ).length;
  }
  get processingCount() {
    return this.allOrders.filter((o) => o.status === "Activated").length;
  }

  get isEmpty() {
    return (
      !this.isLoading && this.filteredOrders.length === 0 && !this.errorMessage
    );
  }
  get hasOrders() {
    return !this.isLoading && this.filteredOrders.length > 0;
  }

  // ── Badge classes ────────────────────────────────────────
  get allBadgeClass() {
    return "stat-badge stat-all" + (this.statusFilter === "" ? " active" : "");
  }
  get paidBadgeClass() {
    return (
      "stat-badge stat-paid" + (this.statusFilter === "Paid" ? " active" : "")
    );
  }
  get codBadgeClass() {
    return (
      "stat-badge stat-pending" +
      (this.statusFilter === "Awaiting Delivery Payment" ? " active" : "")
    );
  }
  get processingBadgeClass() {
    return (
      "stat-badge stat-processing" +
      (this.statusFilter === "Activated" ? " active" : "")
    );
  }

  get hasActiveFilters() {
    return (
      this.searchTerm ||
      this.statusFilter ||
      this.paymentFilter ||
      this.sortOrder !== "date-desc"
    );
  }

  // ── Pagination ───────────────────────────────────────────
  get totalPages() {
    return Math.ceil(this.filteredOrders.length / PAGE_SIZE);
  }
  get isFirstPage() {
    return this.currentPage === 1;
  }
  get isLastPage() {
    return this.currentPage >= this.totalPages;
  }

  get paginatedOrders() {
    const start = (this.currentPage - 1) * PAGE_SIZE;
    return this.filteredOrders.slice(start, start + PAGE_SIZE);
  }

  get pageNumbers() {
    return Array.from({ length: this.totalPages }, (_, i) => ({
      num: i + 1,
      cssClass: i + 1 === this.currentPage ? "page-num active" : "page-num"
    }));
  }

  // Status getters
  get isStatusAll() {
    return this.statusFilter === "";
  }
  get isStatusPaid() {
    return this.statusFilter === "Paid";
  }
  get isStatusActivated() {
    return this.statusFilter === "Activated";
  }
  get isStatusCOD() {
    return this.statusFilter === "Awaiting Delivery Payment";
  }
  get isStatusDraft() {
    return this.statusFilter === "Draft";
  }

  // Payment getters
  get isPaymentAll() {
    return this.paymentFilter === "";
  }
  get isPaymentCard() {
    return this.paymentFilter === "Card";
  }
  get isPaymentCOD() {
    return this.paymentFilter === "COD";
  }

  // Sort getters
  get isSortDateDesc() {
    return this.sortOrder === "date-desc";
  }
  get isSortDateAsc() {
    return this.sortOrder === "date-asc";
  }
  get isSortAmountDesc() {
    return this.sortOrder === "amount-desc";
  }
  get isSortAmountAsc() {
    return this.sortOrder === "amount-asc";
  }

  prevPage() {
    if (!this.isFirstPage) this.currentPage--;
  }
  nextPage() {
    if (!this.isLastPage) this.currentPage++;
  }
  goToPage(e) {
    this.currentPage = parseInt(e.currentTarget.dataset.page, 10);
  }

  // ── Filters ──────────────────────────────────────────────
  handleSearch(event) {
    this.searchTerm = event.target.value;
    this.currentPage = 1;
    this.applyFilters();
  }

  handleStatusFilter(event) {
    this.statusFilter = event.target.value;
    this.currentPage = 1;
    this.applyFilters();
  }

  handlePaymentFilter(event) {
    this.paymentFilter = event.target.value;
    this.currentPage = 1;
    this.applyFilters();
  }

  handleSortFilter(event) {
    this.sortOrder = event.target.value;
    this.currentPage = 1;
    this.applyFilters();
  }

  filterByStatus(event) {
    this.statusFilter = event.currentTarget.dataset.status;
    this.currentPage = 1;
    this.applyFilters();
  }

  // FIX : reset complet — les selects se réinitialisent automatiquement
  // car ils sont liés aux variables @track via value={...}
  resetFilters() {
    this.searchTerm = "";
    this.statusFilter = "";
    this.paymentFilter = "";
    this.sortOrder = "date-desc";
    this.currentPage = 1;
    this.applyFilters();
  }

  applyFilters() {
    let result = [...this.allOrders];

    // Search
    if (this.searchTerm) {
      const term = this.searchTerm.toLowerCase();
      result = result.filter(
        (o) => o.orderNumber && o.orderNumber.toLowerCase().includes(term)
      );
    }

    // Status
    if (this.statusFilter) {
      result = result.filter((o) => o.status === this.statusFilter);
    }

    // Payment
    if (this.paymentFilter) {
      result = result.filter((o) => o.paymentMethod === this.paymentFilter);
    }

    // Sort
    result.sort((a, b) => {
      if (this.sortOrder === "date-asc")
        return a.orderDate > b.orderDate ? 1 : -1;
      if (this.sortOrder === "date-desc")
        return a.orderDate < b.orderDate ? 1 : -1;
      if (this.sortOrder === "amount-asc")
        return parseFloat(a.totalTTC) - parseFloat(b.totalTTC);
      if (this.sortOrder === "amount-desc")
        return parseFloat(b.totalTTC) - parseFloat(a.totalTTC);
      return 0;
    });

    this.filteredOrders = result;
  }

  // ── Order Detail ─────────────────────────────────────────
  handleOrderClick(event) {
    const orderId = event.currentTarget.dataset.id;
    this.showModal = true;
    this.isLoadingDetail = true;
    this.selectedOrder = { orderNumber: "", orderDate: "" };

    getOrderDetail({ orderId })
      .then((data) => {
        this.isLoadingDetail = false;
        this.selectedOrder = {
          ...data,
          subtotal: data.subtotal
            ? parseFloat(data.subtotal).toFixed(2)
            : "0.00",
          taxAmount: data.taxAmount
            ? parseFloat(data.taxAmount).toFixed(2)
            : "0.00",
          shippingCost: data.shippingCost
            ? parseFloat(data.shippingCost).toFixed(2)
            : "0.00",
          discount: data.discount
            ? parseFloat(data.discount).toFixed(2)
            : "0.00",
          totalTTC: data.totalTTC
            ? parseFloat(data.totalTTC).toFixed(2)
            : "0.00",
          taxRate: data.taxRate ? parseFloat(data.taxRate).toFixed(0) : "0",
          hasDiscount: data.discount && parseFloat(data.discount) > 0,
          isFreeShipping:
            !data.shippingCost || parseFloat(data.shippingCost) === 0,
          statusLabel: this.getStatusLabel(data.status),
          statusClass: this.getStatusClass(data.status),
          items: data.items
            ? data.items.map((i) => ({
                ...i,
                totalPrice: i.totalPrice
                  ? parseFloat(i.totalPrice).toFixed(2)
                  : "0.00"
              }))
            : []
        };
      })
      .catch((error) => {
        this.isLoadingDetail = false;
        this.errorMessage = error.body
          ? error.body.message
          : "Error loading detail.";
      });
  }

  closeModal() {
    this.showModal = false;
    this.selectedOrder = null;
  }
  stopPropagation(event) {
    event.stopPropagation();
  }

  // ── Buy Again ────────────────────────────────────────────
  handleReorder(event) {
    const orderId = event.currentTarget.dataset.id;

    getOrderDetail({ orderId })
      .then((data) => {
        if (!data.items || data.items.length === 0) return;
        const promises = data.items.map((item) =>
          addToCart({
            productId: item.productId,
            productName: item.name,
            productImage: item.image,
            unitPrice: item.unitPrice,
            quantity: item.quantity
          })
        );
        return Promise.all(promises);
      })
      .then(() => {
        // Notifier le cart drawer
        window.dispatchEvent(new CustomEvent("cartUpdated"));
        this.showReorderToast = true;
        setTimeout(() => {
          this.showReorderToast = false;
        }, 3000);
      })
      .catch(() => {
        this.errorMessage = "Failed to add items to cart.";
      });
  }

  // ── Download Invoice ─────────────────────────────────────

  handleDownloadInvoice(event) {
    const orderId = event.currentTarget.dataset.id;

    getInvoicePdfUrl({ orderId })
      .then((url) => {
        if (url) {
          window.open(url, "_blank");
        }
      })
      .catch((error) => {
        console.error("Invoice error:", error);
        this.errorMessage = error.body
          ? error.body.message
          : "Failed to generate invoice.";
      });
  }

  // ── Helpers ──────────────────────────────────────────────
  getStatusLabel(status) {
    const map = {
      Paid: "✓ Paid",
      Activated: "⏳ Processing",
      "Awaiting Delivery Payment": "🚚 COD",
      Draft: "📝 Draft",
      Cancelled: "✗ Cancelled"
    };
    return map[status] || status;
  }

  getStatusClass(status) {
    if (status === "Paid") return "status-paid";
    if (status === "Activated") return "status-activated";
    if (status === "Awaiting Delivery Payment") return "status-pending";
    return "status-default";
  }
  handleReturn(event) {
    const orderId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: "/TalFlowExpress/s/order/" + orderId + "/return"
      }
    });
  }
}
