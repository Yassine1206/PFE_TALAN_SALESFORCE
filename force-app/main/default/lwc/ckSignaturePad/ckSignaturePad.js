import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveSignature from "@salesforce/apex/CkContractSignatureController.saveSignature";

export default class CkSignaturePad extends LightningElement {
  @api contractId;
  @api contractNumber;
  @api customerName; // Pre-fill the name field

  @track isOpen = false;
  @track isLoading = false;
  @track signerName = "";
  @track hasDrawn = false;

  canvas;
  ctx;
  isDrawing = false;
  lastX = 0;
  lastY = 0;

  @api
  open() {
    this.isOpen = true;
    this.signerName = this.customerName || "";
    this.hasDrawn = false;

    // Initialize canvas after render
    setTimeout(() => {
      this.initCanvas();
    }, 100);
  }

  close() {
    this.isOpen = false;
    this.hasDrawn = false;
    this.signerName = "";
  }

  initCanvas() {
    this.canvas = this.template.querySelector("canvas");
    if (!this.canvas) return;

    // High DPI support
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    this.canvas.width = rect.width * dpr;
    this.canvas.height = rect.height * dpr;

    this.ctx = this.canvas.getContext("2d");
    this.ctx.scale(dpr, dpr);
    this.ctx.lineWidth = 2.5;
    this.ctx.lineCap = "round";
    this.ctx.lineJoin = "round";
    this.ctx.strokeStyle = "#0A1628";

    // Bind events
    this.canvas.addEventListener("mousedown", this.startDrawing);
    this.canvas.addEventListener("mousemove", this.draw);
    this.canvas.addEventListener("mouseup", this.stopDrawing);
    this.canvas.addEventListener("mouseout", this.stopDrawing);

    // Touch support
    this.canvas.addEventListener("touchstart", this.handleTouchStart);
    this.canvas.addEventListener("touchmove", this.handleTouchMove);
    this.canvas.addEventListener("touchend", this.stopDrawing);
  }

  startDrawing = (e) => {
    this.isDrawing = true;
    const rect = this.canvas.getBoundingClientRect();
    this.lastX = e.clientX - rect.left;
    this.lastY = e.clientY - rect.top;
  };

  draw = (e) => {
    if (!this.isDrawing) return;

    const rect = this.canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    this.ctx.beginPath();
    this.ctx.moveTo(this.lastX, this.lastY);
    this.ctx.lineTo(x, y);
    this.ctx.stroke();

    this.lastX = x;
    this.lastY = y;
    this.hasDrawn = true;
  };

  stopDrawing = () => {
    this.isDrawing = false;
  };

  handleTouchStart = (e) => {
    e.preventDefault();
    const touch = e.touches[0];
    const rect = this.canvas.getBoundingClientRect();
    this.isDrawing = true;
    this.lastX = touch.clientX - rect.left;
    this.lastY = touch.clientY - rect.top;
  };

  handleTouchMove = (e) => {
    e.preventDefault();
    if (!this.isDrawing) return;

    const touch = e.touches[0];
    const rect = this.canvas.getBoundingClientRect();
    const x = touch.clientX - rect.left;
    const y = touch.clientY - rect.top;

    this.ctx.beginPath();
    this.ctx.moveTo(this.lastX, this.lastY);
    this.ctx.lineTo(x, y);
    this.ctx.stroke();

    this.lastX = x;
    this.lastY = y;
    this.hasDrawn = true;
  };

  handleClear() {
    if (this.ctx && this.canvas) {
      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
      this.hasDrawn = false;
    }
  }

  handleNameChange(event) {
    this.signerName = event.target.value;
  }

  async handleSign() {
    if (!this.hasDrawn) {
      this.showToast("Required", "Please sign in the box", "warning");
      return;
    }

    if (!this.signerName || this.signerName.trim().length < 2) {
      this.showToast("Required", "Please enter your full name", "warning");
      return;
    }

    this.isLoading = true;

    try {
      // Get base64 from canvas
      const dataUrl = this.canvas.toDataURL("image/png");

      // Save via Apex
      await saveSignature({
        contractId: this.contractId,
        signatureBase64: dataUrl,
        signedByName: this.signerName.trim()
      });

      this.showToast(
        "Success!",
        "Contract " + this.contractNumber + " signed successfully.",
        "success"
      );

      // Dispatch event so parent can refresh
      this.dispatchEvent(
        new CustomEvent("signed", {
          detail: { contractId: this.contractId }
        })
      );

      this.close();
    } catch (error) {
      const msg = error.body
        ? error.body.message
        : error.message || "Failed to save signature";
      this.showToast("Error", msg, "error");
    } finally {
      this.isLoading = false;
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

  get isSignDisabled() {
    // Disable when can't sign (inverse of canSign)
    return (
      !this.hasDrawn ||
      !this.signerName ||
      this.signerName.trim().length < 2 ||
      this.isLoading
    );
  }

  get signButtonLabel() {
    return this.isLoading ? "Signing..." : "Sign Contract";
  }
}
