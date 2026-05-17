import { LightningElement, track, wire } from "lwc";
import getMyInvoices from "@salesforce/apex/CkInvoiceController.getMyInvoices";
import getStats from "@salesforce/apex/CkInvoiceController.getMyInvoicesStats";
import getInvoiceDetail from "@salesforce/apex/CkInvoiceController.getInvoiceDetail";
import getInvoicePdfUrl from "@salesforce/apex/CkPdfService.getInvoicePdfUrl";
import { applyThemeToComponent } from "c/ckThemeUtils";

export default class CkMyInvoices extends LightningElement {
  @track allInvoices = [];
  @track filteredInvoices = [];
  @track stats = {
    totalInvoices: 0,
    totalPaid: 0,
    unpaidAmount: 0,
    overdueCount: 0
  };
  @track isLoading = true;
  @track errorMessage = "";

  @track activeFilter = "all";
  @track searchTerm = "";

  @track isDetailOpen = false;
  @track selectedInvoice = null;
  @track isLoadingDetail = false;

  connectedCallback() {
    applyThemeToComponent(this);
  }

  @wire(getMyInvoices)
  wiredInvoices({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.allInvoices = data.map((i) => ({
        ...i,
        totalFormatted: this.formatCurrency(i.totalTTC),
        displayStatus: i.isOverdue ? "Overdue" : i.status,
        displayClass: i.isOverdue ? "inv-status-overdue" : i.statusClass
      }));
      this.applyFilters();
    }
    if (error) {
      this.errorMessage = error.body
        ? error.body.message
        : "Failed to load invoices.";
    }
  }

  @wire(getStats)
  wiredStats({ data }) {
    if (data) {
      this.stats = {
        ...data,
        totalPaidFormatted: this.formatCurrency(data.totalPaid),
        unpaidAmountFormatted: this.formatCurrency(data.unpaidAmount)
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
    let filtered = [...this.allInvoices];

    if (this.activeFilter !== "all") {
      filtered = filtered.filter((i) => {
        if (this.activeFilter === "paid") return i.status === "Paid";
        if (this.activeFilter === "unpaid")
          return i.status !== "Paid" && !i.isOverdue;
        if (this.activeFilter === "overdue") return i.isOverdue;
        if (this.activeFilter === "draft") return i.status === "Draft";
        return true;
      });
    }

    if (this.searchTerm.trim()) {
      const term = this.searchTerm.toLowerCase();
      filtered = filtered.filter(
        (i) =>
          i.invoiceNumber.toLowerCase().includes(term) ||
          (i.orderNumber && i.orderNumber.toLowerCase().includes(term))
      );
    }

    this.filteredInvoices = filtered;
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
    const invoiceId = event.currentTarget.dataset.id;
    if (!invoiceId) return;

    this.isDetailOpen = true;
    this.isLoadingDetail = true;
    this.selectedInvoice = null;

    try {
      const detail = await getInvoiceDetail({ invoiceId });
      this.selectedInvoice = {
        ...detail,
        subtotalFormatted: this.formatCurrency(detail.subtotal),
        taxFormatted: this.formatCurrency(detail.taxAmount),
        shippingFormatted: this.formatCurrency(detail.shippingCost),
        discountFormatted: this.formatCurrency(detail.discount),
        totalFormatted: this.formatCurrency(detail.totalTTC),
        hasDiscount: detail.discount && detail.discount > 0
      };
    } catch (error) {
      this.errorMessage = error.body
        ? error.body.message
        : "Failed to load invoice details";
    } finally {
      this.isLoadingDetail = false;
    }
  }

  handleCloseDetail() {
    this.isDetailOpen = false;
    this.selectedInvoice = null;
  }

  handleDownloadInvoice(event) {
    event.stopPropagation();
    const orderId = event.currentTarget.dataset.orderid;
    if (!orderId) {
      this.errorMessage = "No order linked to this invoice";
      return;
    }

    getInvoicePdfUrl({ orderId })
      .then((url) => {
        if (url) {
          window.open(url, "_blank");
        }
      })
      .catch((error) => {
        this.errorMessage = error.body
          ? error.body.message
          : "Failed to download invoice PDF";
      });
  }

  handleDownloadFromModal() {
    if (!this.selectedInvoice || !this.selectedInvoice.orderId) {
      this.errorMessage = "No order linked to this invoice";
      return;
    }

    getInvoicePdfUrl({ orderId: this.selectedInvoice.orderId })
      .then((url) => {
        if (url) {
          window.open(url, "_blank");
        }
      })
      .catch((error) => {
        this.errorMessage = error.body
          ? error.body.message
          : "Failed to download invoice PDF";
      });
  }

  // Getters
  get isEmpty() {
    return (
      !this.isLoading &&
      this.filteredInvoices.length === 0 &&
      !this.errorMessage
    );
  }

  get hasInvoices() {
    return !this.isLoading && this.filteredInvoices.length > 0;
  }

  get filterAllClass() {
    return this.activeFilter === "all" ? "filter-btn active" : "filter-btn";
  }
  get filterPaidClass() {
    return this.activeFilter === "paid" ? "filter-btn active" : "filter-btn";
  }
  get filterUnpaidClass() {
    return this.activeFilter === "unpaid" ? "filter-btn active" : "filter-btn";
  }
  get filterOverdueClass() {
    return this.activeFilter === "overdue" ? "filter-btn active" : "filter-btn";
  }
  get filterDraftClass() {
    return this.activeFilter === "draft" ? "filter-btn active" : "filter-btn";
  }

  get filteredCount() {
    return this.filteredInvoices.length;
  }
}
