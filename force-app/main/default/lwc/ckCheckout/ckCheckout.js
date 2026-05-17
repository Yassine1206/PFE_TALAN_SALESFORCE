import { LightningElement, track, wire } from "lwc";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import ACCOUNT_OBJECT from "@salesforce/schema/Account";
import SHIPPING_COUNTRY_FIELD from "@salesforce/schema/Account.ShippingCountryCode";
import getCheckoutData from "@salesforce/apex/CkCheckoutController.getCheckoutData";
import recalculateTaxes from "@salesforce/apex/CkCheckoutController.recalculateTaxes";
import validatePromoCode from "@salesforce/apex/CkCheckoutController.validatePromoCode";
import processCheckout from "@salesforce/apex/CkCheckoutController.processCheckout";
import createStripeSessionWithOrder from "@salesforce/apex/CkCheckoutController.createStripeSessionWithOrder";

export default class CkCheckout extends LightningElement {
  @track currentStep = 1;
  @track isLoading = false;
  @track isTaxLoading = false;
  @track errorMessage = "";
  @track promoMessage = "";
  @track promoValid = false;
  @track cartItems = [];

  @track form = {
    fullName: "",
    email: "",
    street: "",
    city: "",
    state: "",
    postalCode: "",
    countryCode: "TN",
    phone: "",
    promoCode: "",
    paymentMethod: "Card"
  };

  @track summary = {
    subtotal: 0,
    discount: 0,
    taxRate: 0,
    taxAmount: 0,
    shippingCost: 0,
    totalTTC: 0,
    deliveryDays: "",
    isFallbackRate: false
  };

  // ── Wire picklist pays depuis Account.ShippingCountryCode ─
  @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
  objectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$objectInfo.data.defaultRecordTypeId",
    fieldApiName: SHIPPING_COUNTRY_FIELD
  })
  shippingCountryPicklist;

  // ── Country options depuis picklist Salesforce ────────────
  get countries() {
    const values = this.shippingCountryPicklist?.data?.values;
    if (!values) return [];
    return values.map((v) => ({
      value: v.value,
      label: v.label,
      selected: v.value === this.form.countryCode
    }));
  }

  connectedCallback() {
    this.loadCheckoutData();
  }

  loadCheckoutData() {
    this.isLoading = true;
    getCheckoutData()
      .then((data) => {
        if (data.isGuest) {
          window.location.href = "/s/login";
          return;
        }
        this.form = {
          ...this.form,
          fullName: data.fullName || "",
          email: data.email || "",
          street: data.street || "",
          city: data.city || "",
          state: data.state || "",
          postalCode: data.postalCode || "",
          countryCode: data.country || "TN",
          phone: data.phone || ""
        };
        this.cartItems = (data.items || []).map((i) => ({
          id: i.itemId,
          name: i.name,
          image: i.image,
          quantity: i.quantity,
          price: "$" + (i.unitPrice || 0).toFixed(2)
        }));
        if (data.summary) {
          this.summary = { ...data.summary };
        }
        this.isLoading = false;
      })
      .catch(() => {
        this.isLoading = false;
        this.errorMessage = "Failed to load checkout data.";
      });
  }

  // ── Inputs ────────────────────────────────────────────────
  handleInput(event) {
    const field = event.currentTarget.dataset.field;
    this.form = { ...this.form, [field]: event.target.value };
    this.errorMessage = "";
  }

  // FIX : countryCode vient de la picklist → valeur ISO garantie
  handleCountryChange(event) {
    this.form = { ...this.form, countryCode: event.target.value };
    this.refreshTaxes();
  }

  refreshTaxes(discountOverride) {
    this.isTaxLoading = true;
    const discount =
      discountOverride !== undefined
        ? discountOverride
        : this.summary.discount || 0;

    recalculateTaxes({
      subtotal: this.summary.subtotal,
      countryCode: this.form.countryCode,
      discountAmount: discount
    })
      .then((s) => {
        this.summary = { ...s };
        this.isTaxLoading = false;
      })
      .catch(() => {
        this.isTaxLoading = false;
      });
  }

  // ── Promo ─────────────────────────────────────────────────
  applyPromo() {
    if (!this.form.promoCode) return;
    validatePromoCode({
      code: this.form.promoCode,
      subtotal: this.summary.subtotal
    })
      .then((result) => {
        this.promoValid = result.valid;
        this.promoMessage = result.message;
        if (result.valid) this.refreshTaxes(result.discountAmount);
      })
      .catch(() => {
        this.promoMessage = "Error validating promo code.";
      });
  }

  // ── Navigation ────────────────────────────────────────────
  goStep1() {
    this.currentStep = 1;
    this.errorMessage = "";
  }
  goStep2() {
    if (!this.validateStep1()) return;
    this.currentStep = 2;
    this.refreshTaxes();
  }
  goStep3() {
    this.currentStep = 3;
    this.errorMessage = "";
  }
  goStep4() {
    this.currentStep = 4;
    this.errorMessage = "";
  }

  // ── Payment ───────────────────────────────────────────────
  selectCard() {
    this.form = { ...this.form, paymentMethod: "Card" };
  }
  selectCOD() {
    this.form = { ...this.form, paymentMethod: "COD" };
  }

  // ── Place Order ───────────────────────────────────────────
  placeOrder() {
    this.isLoading = true;
    this.errorMessage = "";

    processCheckout({
      street: this.form.street || "",
      city: this.form.city || "",
      state: this.form.state || "",
      postalCode: this.form.postalCode || "",
      countryCode: this.form.countryCode || "TN",
      email: this.form.email || "",
      phone: this.form.phone || "",
      paymentMethod: this.form.paymentMethod || "Card",
      discountAmount: this.summary.discount || 0,
      promoCode: this.form.promoCode || ""
    })
      .then((result) => {
        if (!result.success) {
          this.isLoading = false;
          this.errorMessage = result.errorMessage || "An error occurred.";
          return null;
        }

        if (this.form.paymentMethod === "COD") {
          this.isLoading = false;
          window.location.href = result.redirectUrl;
          return null;
        }

        const parts = (result.redirectUrl || "").split(":::");
        const orderId = parts[1];

        if (!orderId) {
          this.isLoading = false;
          this.errorMessage = "Order ID missing.";
          return null;
        }

        return createStripeSessionWithOrder({
          orderId: orderId,
          total: this.summary.totalTTC,
          email: this.form.email || ""
        });
      })
      .then((stripeUrl) => {
        if (!stripeUrl) return;
        this.isLoading = false;
        window.location.href = stripeUrl;
      })
      .catch((error) => {
        this.isLoading = false;
        this.errorMessage =
          error.body && error.body.message
            ? error.body.message
            : "An error occurred. Please try again.";
      });
  }

  // ── Validation ────────────────────────────────────────────
  validateStep1() {
    const f = this.form;
    if (!f.fullName || !f.email || !f.street || !f.city || !f.countryCode) {
      this.errorMessage = "Please fill all required fields.";
      return false;
    }
    if (!f.email.includes("@")) {
      this.errorMessage = "Please enter a valid email address.";
      return false;
    }
    this.errorMessage = "";
    return true;
  }

  // ── Getters ───────────────────────────────────────────────
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

  get isCardSelected() {
    return this.form.paymentMethod === "Card";
  }
  get isCODSelected() {
    return this.form.paymentMethod === "COD";
  }

  get hasDiscount() {
    return this.summary.discount && this.summary.discount > 0;
  }

  get steps() {
    const labels = ["Address", "Shipping", "Payment", "Review"];
    return labels.map((label, i) => ({
      id: i + 1,
      num: i + 1,
      label,
      cls:
        "ck-step" +
        (this.currentStep === i + 1 ? " ck-step-active" : "") +
        (this.currentStep > i + 1 ? " ck-step-completed" : "")
    }));
  }

  get cardMethodCls() {
    return "ck-method" + (this.isCardSelected ? " ck-method-selected" : "");
  }
  get codMethodCls() {
    return "ck-method" + (this.isCODSelected ? " ck-method-selected" : "");
  }
  get paymentMethodBadge() {
    return this.isCODSelected
      ? "ck-payment-badge ck-badge-green"
      : "ck-payment-badge";
  }
  get promoMessageCls() {
    return this.promoValid ? "ck-promo-success" : "ck-promo-error";
  }
  get countryLabel() {
    const values = this.shippingCountryPicklist?.data?.values;
    if (!values) return this.form.countryCode;
    const found = values.find((v) => v.value === this.form.countryCode);
    return found ? found.label : this.form.countryCode;
  }
}
