import { LightningElement, track, wire } from "lwc";
import getB2BProducts from "@salesforce/apex/CkQuoteController.getB2BProducts";
import submitQuoteRequest from "@salesforce/apex/CkQuoteController.submitQuoteRequest";
import isB2BUser from "@salesforce/apex/CkUserController.isB2BUser";

export default class CkRequestQuote extends LightningElement {
  @track products = [];
  @track isLoading = true;
  @track currentStep = 1;
  @track step1Error = "";
  @track step2Error = "";
  @track submitError = "";
  @track isSubmitting = false;
  @track quoteResult = null;

  @track form = {
    shippingAddress: "",
    shippingCity: "",
    shippingZip: "",
    shippingCountry: "",
    deliveryDate: "",
    comments: "",
    isUrgent: false,
    urgencyReason: ""
  };

  @wire(getB2BProducts)
  wiredProducts({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.products = data.map((p) => ({
        ...p,
        quantity: 0
      }));
    }
    if (error) {
      this.step1Error = "Failed to load products.";
    }
  }
  @wire(isB2BUser)
  wiredIsB2B({ data, error }) {
    if (data === false) {
      this.errorMessage = "This page is reserved for B2B customers only.";
      this.isLoading = false;
    }
  }

  // ── Steps ───────────────────────────────────────────────
  get isStep1() {
    return this.currentStep === 1;
  }
  get isStep2() {
    return this.currentStep === 2;
  }
  get isStep3() {
    return this.currentStep === 3;
  }
  get isStep4() {
    return this.currentStep === 4;
  }

  get step1Class() {
    return this.getStepClass(1);
  }
  get step2Class() {
    return this.getStepClass(2);
  }
  get step3Class() {
    return this.getStepClass(3);
  }

  getStepClass(step) {
    if (this.currentStep === step) return "rq-step rq-step-active";
    if (this.currentStep > step) return "rq-step rq-step-done";
    return "rq-step";
  }

  // ── Min delivery date (14 days from today) ───────────────
  get minDeliveryDate() {
    const d = new Date();
    d.setDate(d.getDate() + 14);
    return d.toISOString().split("T")[0];
  }

  // ── Selected items ───────────────────────────────────────
  get selectedItems() {
    return this.products
      .filter((p) => p.quantity > 0)
      .map((p) => ({
        ...p,
        lineTotal: (p.b2bPrice * p.quantity).toFixed(2)
      }));
  }

  get hasSelectedItems() {
    return this.selectedItems.length > 0;
  }

  get totalItems() {
    return this.selectedItems.reduce((sum, p) => sum + p.quantity, 0);
  }

  get subtotal() {
    return this.selectedItems
      .reduce((sum, p) => sum + p.b2bPrice * p.quantity, 0)
      .toFixed(2);
  }

  get discountPercent() {
    const s = parseFloat(this.subtotal);
    if (s >= 10000) return 15;
    if (s >= 5000) return 5;
    return 0;
  }

  get hasDiscount() {
    return this.discountPercent > 0;
  }

  get discountAmount() {
    return ((parseFloat(this.subtotal) * this.discountPercent) / 100).toFixed(
      2
    );
  }

  get subtotalAfterDiscount() {
    return (
      parseFloat(this.subtotal) - parseFloat(this.discountAmount)
    ).toFixed(2);
  }

  get taxAmount() {
    return (parseFloat(this.subtotalAfterDiscount) * 0.19).toFixed(2);
  }

  get totalTTC() {
    return (
      parseFloat(this.subtotalAfterDiscount) + parseFloat(this.taxAmount)
    ).toFixed(2);
  }

  // ── Validations ──────────────────────────────────────────
  get showMinAmountWarning() {
    return this.hasSelectedItems && parseFloat(this.subtotal) < 1000;
  }

  get showMinItemsWarning() {
    return this.hasSelectedItems && this.totalItems < 5;
  }

  get isStep1Disabled() {
    return (
      !this.hasSelectedItems ||
      parseFloat(this.subtotal) < 1000 ||
      this.totalItems < 5
    );
  }

  // ── Quantity handlers ────────────────────────────────────
  increaseQty(event) {
    const id = event.currentTarget.dataset.id;
    this.products = this.products.map((p) => {
      if (p.productId === id && p.quantity < p.stock) {
        return { ...p, quantity: p.quantity + 1 };
      }
      return p;
    });
  }

  decreaseQty(event) {
    const id = event.currentTarget.dataset.id;
    this.products = this.products.map((p) => {
      if (p.productId === id && p.quantity > 0) {
        return { ...p, quantity: p.quantity - 1 };
      }
      return p;
    });
  }

  // ── Form handlers ────────────────────────────────────────
  handleFormInput(event) {
    const field = event.currentTarget.dataset.field;
    this.form = { ...this.form, [field]: event.target.value };
  }

  handleUrgentToggle(event) {
    this.form = { ...this.form, isUrgent: event.target.checked };
    if (!event.target.checked) {
      this.form.urgencyReason = "";
    }
  }

  // ── Navigation ───────────────────────────────────────────
  goToStep1() {
    this.currentStep = 1;
    this.step2Error = "";
  }

  goToStep2() {
    this.step1Error = "";
    if (this.isStep1Disabled) {
      this.step1Error =
        "Please select at least 5 items with a total of 1,000 TND.";
      return;
    }
    this.currentStep = 2;
  }

  goToStep3() {
    this.step2Error = "";
    if (!this.form.shippingAddress.trim()) {
      this.step2Error = "Please enter the shipping address.";
      return;
    }
    if (!this.form.shippingCity.trim()) {
      this.step2Error = "Please enter the city.";
      return;
    }
    if (!this.form.shippingCountry.trim()) {
      this.step2Error = "Please enter the country.";
      return;
    }
    if (!this.form.deliveryDate) {
      this.step2Error = "Please select a requested delivery date.";
      return;
    }
    this.currentStep = 3;
  }

  get showUrgencyReason() {
    return this.form.isUrgent;
  }

  // ── Submit ───────────────────────────────────────────────
  handleSubmit() {
    this.isSubmitting = true;
    this.submitError = "";

    const items = this.selectedItems.map((p) => ({
      productId: p.productId,
      productName: p.name,
      unitPrice: p.b2bPrice,
      quantity: p.quantity
    }));

    submitQuoteRequest({
      itemsJson: JSON.stringify(items),
      shippingAddress: this.form.shippingAddress,
      shippingCity: this.form.shippingCity,
      shippingCountry: this.form.shippingCountry,
      shippingZip: this.form.shippingZip,
      requestedDeliveryDate: this.form.deliveryDate,
      comments: this.form.comments,
      isUrgent: this.form.isUrgent,
      urgencyReason: this.form.urgencyReason
    })
      .then((result) => {
        this.isSubmitting = false;
        this.quoteResult = {
          ...result,
          totalTTC: parseFloat(result.totalTTC).toFixed(2),
          discountAmount: parseFloat(result.discountAmount).toFixed(2)
        };
        this.currentStep = 4;
      })
      .catch((error) => {
        this.isSubmitting = false;
        this.submitError = error.body
          ? error.body.message
          : "Failed to submit quote.";
      });
  }
}
