import { LightningElement, track } from "lwc";
import confirmOrder from "@salesforce/apex/CkCheckoutController.confirmOrder";

export default class CkOrderConfirmation extends LightningElement {
  @track isLoading = true;
  @track isSuccess = false;
  @track errorMessage = "";
  @track orderNumber = "";
  @track totalTTC = "";
  @track paymentMethod = "";
  @track shippingTo = "";
  @track orderDate = "";
  @track shippingStreet = "";
  @track shippingCity = "";
  @track shippingState = "";
  @track shippingZip = "";
  @track shippingCountry = "";
  @track customerEmail = "";
  @track customerPhone = "";

  connectedCallback() {
    this.verifyPayment();
  }

  verifyPayment() {
    const url = new URL(window.location.href);
    const sessionId = url.searchParams.get("session_id");
    const method = url.searchParams.get("method");

    let orderId =
      url.searchParams.get("oid") ||
      url.searchParams.get("orderId") ||
      sessionStorage.getItem("pendingOrderId");
    sessionStorage.removeItem("pendingOrderId");

    // ── COD ──────────────────────────────────────────────
    if (method === "COD") {
      if (!orderId) {
        this.isLoading = false;
        this.errorMessage = "Order not found.";
        return;
      }
      confirmOrder({ orderId: orderId, sessionId: null })
        .then((result) => {
          this.isLoading = false;
          this.isSuccess = result.success;
          if (result.success) {
            this.applyResult(result);
          } else {
            this.errorMessage = "Order confirmation failed.";
          }
        })
        .catch((error) => {
          this.isLoading = false;
          this.errorMessage = error.body
            ? error.body.message
            : "Verification failed.";
        });
      return;
    }

    // ── Card (Stripe) ─────────────────────────────────────
    if (!sessionId) {
      this.isLoading = false;
      this.errorMessage = "Invalid payment session.";
      return;
    }

    confirmOrder({ orderId: orderId, sessionId: sessionId })
      .then((result) => {
        this.isLoading = false;
        this.isSuccess = result.success;
        if (result.success) {
          this.applyResult(result);
        } else {
          this.errorMessage =
            "Payment verification failed. Please contact support.";
        }
      })
      .catch((error) => {
        this.isLoading = false;
        this.errorMessage = error.body
          ? error.body.message
          : "Verification failed.";
      });
  }

  applyResult(result) {
    this.orderNumber = result.orderNumber || "";
    this.totalTTC = result.totalTTC
      ? Number(result.totalTTC).toFixed(2)
      : "0.00";
    this.paymentMethod = result.paymentMethod || "";
    this.orderDate = result.orderDate || "";
    this.shippingStreet = result.shippingStreet || "";
    this.shippingCity = result.shippingCity || "";
    this.shippingState = result.shippingState || "";
    this.shippingZip = result.shippingZip || "";
    this.shippingCountry = result.shippingCountry || "";
    this.customerEmail = result.customerEmail || "";
    this.customerPhone = result.customerPhone || "";

    // Construire l'adresse complète
    this.shippingTo = [
      this.shippingStreet,
      this.shippingCity,
      this.shippingState,
      this.shippingZip,
      this.shippingCountry
    ]
      .filter((v) => v && v.trim() !== "")
      .join(", ");
  }
}
