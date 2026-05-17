import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getProducts from "@salesforce/apex/CkB2BCatalogController.getProducts";
import getCategories from "@salesforce/apex/CkB2BCatalogController.getCategories";
import submitQuickQuote from "@salesforce/apex/CkB2BCatalogController.submitQuickQuote";
import { applyThemeToComponent } from "c/ckThemeUtils";

export default class CkB2BCatalog extends LightningElement {
  // ─── State ───────────────────────────────────────────────
  isLoading = true;
  hasError = false;
  products = [];
  categories = [];

  // ─── Filters ─────────────────────────────────────────────
  searchTerm = "";
  selectedCategoryId = null;
  minPrice = null;
  maxPrice = null;
  inStockOnly = false;
  onSaleOnly = false;
  topRatedOnly = false;

  // ─── Modal ───────────────────────────────────────────────
  showQuoteModal = false;
  selectedProduct = null;
  modalQuantity = 1;
  modalDeliveryDate = "";
  modalNotes = "";
  modalIsUrgent = false;
  modalUrgencyReason = "";
  isSubmittingQuote = false;
  submitError = "";

  // ─── Toast ───────────────────────────────────────────────
  showToast = false;
  toastMessage = "";
  toastType = "success"; // 'success' | 'error'

  connectedCallback() {
    applyThemeToComponent(this);
  }

  // ─── Wire — Categories ───────────────────────────────────
  @wire(getCategories)
  wiredCategories({ data, error }) {
    if (data) {
      this.categories = data;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("getCategories error:", error);
    }
  }

  // ─── Wire — Products (re-fires on filter change) ─────────
  _wiredProductsResult;

  @wire(getProducts, { filters: "$currentFilters" })
  wiredProducts(result) {
    this._wiredProductsResult = result;
    const { data, error } = result;
    if (data) {
      this.products = data;
      this.isLoading = false;
      this.hasError = false;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("getProducts error:", error);
      this.isLoading = false;
      this.hasError = true;
    }
  }

  get currentFilters() {
    return {
      searchTerm: this.searchTerm,
      categoryId: this.selectedCategoryId,
      minPrice: this.minPrice,
      maxPrice: this.maxPrice,
      inStockOnly: this.inStockOnly,
      onSaleOnly: this.onSaleOnly,
      topRatedOnly: this.topRatedOnly
    };
  }

  // ─── Computed ────────────────────────────────────────────
  get hasProducts() {
    return this.products && this.products.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.hasError && this.products.length === 0;
  }

  get showCatalog() {
    return !this.isLoading && !this.hasError && this.products.length > 0;
  }

  get productCount() {
    return this.products ? this.products.length : 0;
  }

  get categoryOptions() {
    const all = [{ value: "", label: "All Categories" }];
    const cats = this.categories.map((c) => ({
      value: c.categoryId,
      label: `${c.categoryName} (${c.productCount})`
    }));
    return [...all, ...cats];
  }

  // Computed product list with formatted prices for the template
  get displayProducts() {
    return this.products.map((p) => ({
      ...p,
      b2bPriceFormatted: "$" + Number(p.b2bPrice || 0).toFixed(2),
      retailPriceFormatted: p.retailPrice
        ? "$" + Number(p.retailPrice).toFixed(2)
        : null,
      savingsFormatted:
        p.savings > 0 ? "$" + Number(p.savings).toFixed(2) + " off" : null,
      stockLabel: p.inStock ? `${p.stockQuantity} in stock` : "Out of stock",
      stockClass: p.inStock
        ? "ck-stock-badge ck-stock-in"
        : "ck-stock-badge ck-stock-out",
      ratingDisplay: p.rating ? Number(p.rating).toFixed(1) : "—",
      cardClass: p.inStock
        ? "ck-product-card"
        : "ck-product-card ck-product-disabled",
      buttonDisabled: !p.inStock
    }));
  }

  get showModalUrgencyReason() {
    return this.modalIsUrgent;
  }
  // ─── Filter handlers ─────────────────────────────────────
  handleSearchInput(event) {
    this.searchTerm = event.target.value;
  }

  handleCategoryChange(event) {
    const val = event.target.value;
    this.selectedCategoryId = val ? val : null;
  }

  handleMinPriceChange(event) {
    const val = event.target.value;
    this.minPrice = val ? parseFloat(val) : null;
  }

  handleMaxPriceChange(event) {
    const val = event.target.value;
    this.maxPrice = val ? parseFloat(val) : null;
  }

  handleInStockToggle(event) {
    this.inStockOnly = event.target.checked;
  }

  handleOnSaleToggle(event) {
    this.onSaleOnly = event.target.checked;
  }

  handleTopRatedToggle(event) {
    this.topRatedOnly = event.target.checked;
  }

  handleResetFilters() {
    this.searchTerm = "";
    this.selectedCategoryId = null;
    this.minPrice = null;
    this.maxPrice = null;
    this.inStockOnly = false;
    this.onSaleOnly = false;
    this.topRatedOnly = false;

    // Reset DOM inputs
    const searchInput = this.template.querySelector('[data-id="search-input"]');
    if (searchInput) searchInput.value = "";

    const categorySelect = this.template.querySelector(
      '[data-id="category-select"]'
    );
    if (categorySelect) categorySelect.value = "";

    const minInput = this.template.querySelector('[data-id="min-price"]');
    if (minInput) minInput.value = "";

    const maxInput = this.template.querySelector('[data-id="max-price"]');
    if (maxInput) maxInput.value = "";

    ["in-stock", "on-sale", "top-rated"].forEach((id) => {
      const cb = this.template.querySelector(`[data-id="${id}"]`);
      if (cb) cb.checked = false;
    });
  }

  // ─── Modal handlers ──────────────────────────────────────
  handleOpenQuoteModal(event) {
    const productId = event.currentTarget.dataset.productId;
    const product = this.products.find((p) => p.productId === productId);
    if (!product || !product.inStock) return;

    this.selectedProduct = product;
    this.modalQuantity = 1;

    // Default delivery date = today + 15 days (formatted YYYY-MM-DD)
    const future = new Date();
    future.setDate(future.getDate() + 15);
    this.modalDeliveryDate = future.toISOString().split("T")[0];

    this.modalNotes = "";
    this.modalIsUrgent = false;
    this.modalUrgencyReason = "";
    this.submitError = "";
    this.showQuoteModal = true;
  }

  handleCloseModal() {
    this.showQuoteModal = false;
    this.selectedProduct = null;
    this.submitError = "";
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  handleQuantityChange(event) {
    const val = parseInt(event.target.value, 10);
    this.modalQuantity = Math.max(1, isNaN(val) ? 1 : val);
  }

  handleDeliveryDateChange(event) {
    this.modalDeliveryDate = event.target.value;
  }

  handleNotesChange(event) {
    this.modalNotes = event.target.value;
  }
  handleUrgentToggle(event) {
    this.modalIsUrgent = event.target.checked;
    if (!event.target.checked) {
      this.modalUrgencyReason = "";
    }
  }

  handleUrgencyReasonChange(event) {
    this.modalUrgencyReason = event.target.value;
  }
  incrementQuantity() {
    this.modalQuantity += 1;
  }

  decrementQuantity() {
    if (this.modalQuantity > 1) {
      this.modalQuantity -= 1;
    }
  }

  // ─── Submit Quote ────────────────────────────────────────
  handleSubmitQuote() {
    if (!this.selectedProduct) return;

    if (this.modalQuantity < 1) {
      this.submitError = "Quantity must be at least 1.";
      return;
    }

    if (!this.modalDeliveryDate) {
      this.submitError = "Please select a delivery date.";
      return;
    }

    this.isSubmittingQuote = true;
    this.submitError = "";

    submitQuickQuote({
      productId: this.selectedProduct.productId,
      quantity: this.modalQuantity,
      deliveryDate: this.modalDeliveryDate,
      specialNotes: this.modalNotes,
      isUrgent: this.modalIsUrgent,
      urgencyReason: this.modalUrgencyReason
    })
      .then((quoteId) => {
        this.isSubmittingQuote = false;
        this.showQuoteModal = false;
        this.showToastMessage(
          `Quote request submitted successfully! Our team will contact you soon.`,
          "success"
        );
        this.selectedProduct = null;
      })
      .catch((error) => {
        this.isSubmittingQuote = false;
        this.submitError = error.body
          ? error.body.message
          : "Failed to submit quote. Please try again.";
      });
  }

  // ─── Modal computed ──────────────────────────────────────
  get modalProductPrice() {
    if (!this.selectedProduct) return "$0.00";
    return "$" + Number(this.selectedProduct.b2bPrice || 0).toFixed(2);
  }

  get modalTotal() {
    if (!this.selectedProduct) return "$0.00";
    const total = (this.selectedProduct.b2bPrice || 0) * this.modalQuantity;
    return "$" + Number(total).toFixed(2);
  }

  get submitButtonLabel() {
    return this.isSubmittingQuote ? "Submitting..." : "Submit Quote Request";
  }

  get minDeliveryDate() {
    // Today's date in YYYY-MM-DD
    return new Date().toISOString().split("T")[0];
  }

  // ─── Toast ───────────────────────────────────────────────
  showToastMessage(message, type) {
    this.toastMessage = message;
    this.toastType = type;
    this.showToast = true;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.showToast = false;
    }, 4000);
  }

  get toastClass() {
    return `ck-toast ck-toast-${this.toastType}`;
  }
}
