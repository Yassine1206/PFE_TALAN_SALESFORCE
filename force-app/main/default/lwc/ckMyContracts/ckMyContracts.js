import { LightningElement, track, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getMyContractsWithSignature from "@salesforce/apex/CkContractSignatureController.getMyContractsWithSignature";
import getContractPdfUrl from "@salesforce/apex/CkPdfService.getContractPdfUrl";
import { applyThemeToComponent } from "c/ckThemeUtils";

export default class CkMyContracts extends LightningElement {
  @track contracts = [];
  @track isLoading = true;
  @track errorMessage = "";

  // Signature modal state
  @track selectedContractId = null;
  @track selectedContractNumber = "";
  @track customerName = "";

  wiredContractsResult;

  connectedCallback() {
    applyThemeToComponent(this);
  }

  @wire(getMyContractsWithSignature)
  wiredContracts(result) {
    this.wiredContractsResult = result;
    this.isLoading = false;
    if (result.data) {
      this.contracts = result.data.map((c) => ({
        ...c,
        totalAmount: c.totalAmount
          ? parseFloat(c.totalAmount).toFixed(2)
          : "0.00",
        statusClass: this.getStatusClass(c.status),
        signedDateFormatted: this.formatDate(c.signedDate),
        canSign: c.status === "Draft" && !c.isSigned,
        showSignedBadge: c.isSigned
      }));

      // Pre-fill customer name for the modal
      if (result.data.length > 0) {
        this.customerName = result.data[0].customerName || "";
      }
    }
    if (result.error) {
      this.errorMessage = result.error.body
        ? result.error.body.message
        : "Failed to load contracts.";
    }
  }

  get isEmpty() {
    return !this.isLoading && this.contracts.length === 0 && !this.errorMessage;
  }

  get hasContracts() {
    return !this.isLoading && this.contracts.length > 0;
  }

  getStatusClass(status) {
    if (status === "Activated") return "mc-status mc-status-active";
    if (status === "Draft") return "mc-status mc-status-draft";
    return "mc-status mc-status-default";
  }

  formatDate(dt) {
    if (!dt) return "";
    const d = new Date(dt);
    return (
      d.toLocaleDateString() +
      " " +
      d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    );
  }

  // ── Download Contract PDF (Salesforce-stored) ────────────
  handleDownloadContract(event) {
    const contractId = event.currentTarget.dataset.id;
    if (!contractId) return;
    getContractPdfUrl({ contractId })
      .then((url) => {
        if (url) {
          window.open(url, "_blank");
        } else {
          this.errorMessage = "Failed to generate PDF.";
        }
      })
      .catch((error) => {
        this.errorMessage = error.body
          ? error.body.message
          : "Failed to download PDF.";
      });
  }

  // ── Open Signature Modal ────────────
  handleOpenSign(event) {
    const contractId = event.currentTarget.dataset.id;
    const contractNumber = event.currentTarget.dataset.number;

    if (!contractId) return;

    this.selectedContractId = contractId;
    this.selectedContractNumber = contractNumber;

    // Open the modal via the child component's API
    setTimeout(() => {
      const pad = this.template.querySelector("c-ck-signature-pad");
      if (pad) {
        pad.open();
      }
    }, 50);
  }

  // ── Handle Signature Saved ────────────
  async handleSigned(event) {
    console.log("Contract signed:", event.detail);
    // Refresh contracts to show updated state
    await refreshApex(this.wiredContractsResult);
  }
}
