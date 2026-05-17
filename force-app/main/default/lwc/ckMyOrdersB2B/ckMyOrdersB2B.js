import { LightningElement, track, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getMyOrders from "@salesforce/apex/CkOrderController.getMyOrders";
import { applyThemeToComponent } from "c/ckThemeUtils";
import getMyOrdersStats from "@salesforce/apex/CkOrderController.getMyOrdersB2BStats";
import getOrderDetail from "@salesforce/apex/CkOrderController.getOrderDetail";
import payB2BOrder from "@salesforce/apex/CkOrderController.payB2BOrder";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class CkMyOrdersB2B extends LightningElement {
  @track allOrders = [];
  @track filteredOrders = [];
  @track stats = {
    totalOrders: 0,
    totalSpent: 0,
    pendingCount: 0,
    deliveredCount: 0
  };
  @track isLoading = true;
  @track errorMessage = "";

  // Filters
  @track activeFilter = "all";
  @track searchTerm = "";

  // Modal
  @track isDetailOpen = false;
  @track selectedOrder = null;
  @track isLoadingDetail = false;

  @track isPaymentChoiceOpen = false;
  @track isProcessingPayment = false;
  @track selectedPaymentMethod = null;

  wiredOrdersResult;
  wiredStatsResult;

  connectedCallback() {
    applyThemeToComponent(this);
  }

  @wire(getMyOrders)
  wiredOrders(result) {
    this.wiredOrdersResult = result;
    this.isLoading = false;
    if (result.data) {
      this.allOrders = result.data.map((o) => ({
        ...o,
        // Map vers les champs attendus par le HTML
        effectiveDate: o.orderDate,
        totalAmount: o.totalTTC,
        itemsCount: o.itemCount,
        totalAmountFormatted: this.formatCurrency(o.totalTTC),
        itemsLabel: o.itemCount + (o.itemCount > 1 ? " items" : " item")
      }));
      this.applyFilters();
    }
    if (result.error) {
      this.errorMessage = result.error.body
        ? result.error.body.message
        : "Failed to load orders.";
    }
  }

  @wire(getMyOrdersStats)
  wiredStats(result) {
    this.wiredStatsResult = result;
    if (result.data) {
      this.stats = {
        ...result.data,
        totalSpentFormatted: this.formatCurrency(result.data.totalSpent)
      };
    }
  }

  formatCurrency(val) {
    if (!val) return "$0";
    return (
      "$" + Number(val).toLocaleString("en-US", { maximumFractionDigits: 0 })
    );
  }

  applyFilters() {
    let filtered = [...this.allOrders];

    // Status filter
    if (this.activeFilter !== "all") {
      filtered = filtered.filter((o) => {
        if (this.activeFilter === "pending") {
          return o.status === "Draft" || o.status === "Activated";
        }
        if (this.activeFilter === "shipped") return o.status === "Shipped";
        if (this.activeFilter === "delivered") return o.status === "Delivered";
        if (this.activeFilter === "cancelled") return o.status === "Cancelled";
        return true;
      });
    }

    // Search filter
    if (this.searchTerm.trim()) {
      const term = this.searchTerm.toLowerCase();
      filtered = filtered.filter((o) =>
        o.orderNumber.toLowerCase().includes(term)
      );
    }

    this.filteredOrders = filtered;
  }

  handleFilterClick(event) {
    this.activeFilter = event.currentTarget.dataset.filter;
    this.applyFilters();
  }

  handleSearchChange(event) {
    this.searchTerm = event.target.value;
    this.applyFilters();
  }

  async handleRowClick(event) {
    const orderId = event.currentTarget.dataset.id;
    if (!orderId) return;

    this.isDetailOpen = true;
    this.isLoadingDetail = true;

    try {
      const detail = await getOrderDetail({ orderId });
      this.selectedOrder = {
        ...detail,
        effectiveDate: detail.orderDate,
        totalAmount: detail.totalTTC,
        accountName: detail.shippingCity || "",
        totalAmountFormatted: this.formatCurrency(detail.totalTTC),
        subtotalFormatted: this.formatCurrency(detail.subtotal),
        taxAmountFormatted: this.formatCurrency(detail.taxAmount),
        shippingCostFormatted: this.formatCurrency(detail.shippingCost),
        items: (detail.items || []).map((i) => ({
          ...i,
          unitPriceFormatted: this.formatCurrency(i.unitPrice),
          totalPriceFormatted: this.formatCurrency(i.totalPrice)
        })),
        canPay: detail.status === "Draft" // ← AJOUT
      };
    } catch (error) {
      this.errorMessage = error.body
        ? error.body.message
        : "Failed to load order details";
    } finally {
      this.isLoadingDetail = false;
    }
  }
  handleCloseDetail() {
    this.isDetailOpen = false;
    this.selectedOrder = null;
  }

  handleReorder() {
    // TODO: Implement reorder logic (Phase 2)
    alert("Reorder feature coming soon!");
  }

  // Getters
  get isEmpty() {
    return (
      !this.isLoading && this.filteredOrders.length === 0 && !this.errorMessage
    );
  }

  get hasOrders() {
    return !this.isLoading && this.filteredOrders.length > 0;
  }

  get filterAllClass() {
    return this.activeFilter === "all" ? "filter-btn active" : "filter-btn";
  }
  get filterPendingClass() {
    return this.activeFilter === "pending" ? "filter-btn active" : "filter-btn";
  }
  get filterShippedClass() {
    return this.activeFilter === "shipped" ? "filter-btn active" : "filter-btn";
  }
  get filterDeliveredClass() {
    return this.activeFilter === "delivered"
      ? "filter-btn active"
      : "filter-btn";
  }
  get filterCancelledClass() {
    return this.activeFilter === "cancelled"
      ? "filter-btn active"
      : "filter-btn";
  }

  get filteredCount() {
    return this.filteredOrders.length;
  }

  handlePayNow() {
    this.isPaymentChoiceOpen = true;
  }

  closePaymentChoice() {
    if (this.isProcessingPayment) return;
    this.isPaymentChoiceOpen = false;
  }

  async handlePayByCard() {
    await this.processPayment("Card");
  }

  async handlePayByCOD() {
    await this.processPayment("COD");
  }

  async processPayment(method) {
    if (!this.selectedOrder || !this.selectedOrder.orderId) return;

    this.isProcessingPayment = true;
    this.selectedPaymentMethod = method;

    try {
      const result = await payB2BOrder({
        orderId: this.selectedOrder.orderId,
        paymentMethod: method
      });

      if (result.success && result.redirectUrl) {
        // Redirection
        if (method === "Card") {
          // Stripe checkout (external URL)
          window.location.href = result.redirectUrl;
        } else {
          // COD success page
          this.showToast(
            "Order Confirmed!",
            "Your order " +
              result.orderNumber +
              " is confirmed. Payment on delivery.",
            "success"
          );

          // Close modals and refresh
          this.isPaymentChoiceOpen = false;
          this.handleCloseDetail();

          // Redirect to confirmation
          setTimeout(() => {
            window.location.href = result.redirectUrl;
          }, 1000);
        }
      }
    } catch (error) {
      const msg = error.body ? error.body.message : "Payment failed";
      this.showToast("Payment Error", msg, "error");
      this.isProcessingPayment = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }

  // Nouveaux getters
  get isCardProcessing() {
    return this.isProcessingPayment && this.selectedPaymentMethod === "Card";
  }

  get isCODProcessing() {
    return this.isProcessingPayment && this.selectedPaymentMethod === "COD";
  }

  get cardButtonLabel() {
    return this.isCardProcessing ? "Redirecting to Stripe..." : "Pay by Card";
  }

  get codButtonLabel() {
    return this.isCODProcessing ? "Processing..." : "Pay on Delivery";
  }
}
