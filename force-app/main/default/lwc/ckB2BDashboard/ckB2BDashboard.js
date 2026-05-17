import { LightningElement, wire } from "lwc";
import getDashboardData from "@salesforce/apex/CkB2BDashboardController.getDashboardData";

export default class CkB2BDashboard extends LightningElement {
  isLoading = true;
  hasError = false;
  data = null;

  @wire(getDashboardData)
  wiredDashboard({ error, data }) {
    if (data) {
      this.data = data;
      this.isLoading = false;
      this.hasError = false;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("ckB2BDashboard error:", error);
      this.isLoading = false;
      this.hasError = true;
    }
  }

  // ─── Visibility ───────────────────────────────────────────
  get showDashboard() {
    return !this.isLoading && !this.hasError && this.data != null;
  }

  // ─── User info ────────────────────────────────────────────
  get firstName() {
    const name = this.data?.firstName || "there";
    // Capitalize first letter (chiheb → Chiheb)
    return name.charAt(0).toUpperCase() + name.slice(1).toLowerCase();
  }

  get companyName() {
    const name = this.data?.companyName || "";
    // Uppercase company name
    return name.toUpperCase();
  }

  get todayDate() {
    return new Date().toLocaleDateString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric"
    });
  }

  // ─── KPIs ─────────────────────────────────────────────────
  get totalQuotesPending() {
    return this.data?.totalQuotesPending ?? 0;
  }
  get activeContracts() {
    return this.data?.activeContracts ?? 0;
  }
  get pendingOrders() {
    return this.data?.pendingOrders ?? 0;
  }
  get lastInvoiceStatus() {
    return this.data?.lastInvoiceStatus ?? "—";
  }
  get lastInvoiceDate() {
    return this.data?.lastInvoiceDate ?? "";
  }
  get contractsExpiringSoon() {
    return this.data?.contractsExpiringSoon ?? 0;
  }

  get totalSpentYTDFormatted() {
    const val = this.data?.totalSpentYTD ?? 0;
    return (
      "$" +
      val.toLocaleString("en-US", {
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
      })
    );
  }

  get avgOrderValueFormatted() {
    const val = this.data?.avgOrderValue ?? 0;
    return (
      "$" +
      val.toLocaleString("en-US", {
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
      })
    );
  }

  // ─── KPI 7 — Dynamic classes ──────────────────────────────
  get contractsExpiringSoonClass() {
    return (this.data?.contractsExpiringSoon ?? 0) > 0
      ? "ck-kpi-card ck-kpi-danger"
      : "ck-kpi-card ck-kpi-light";
  }

  get contractsExpiringSoonTrendClass() {
    return (this.data?.contractsExpiringSoon ?? 0) > 0
      ? "ck-kpi-trend ck-trend-danger"
      : "ck-kpi-trend ck-trend-neutral";
  }

  get contractsExpiringSoonLabel() {
    return (this.data?.contractsExpiringSoon ?? 0) > 0 ? "Urgent" : "OK";
  }

  // ─── Chart getters ────────────────────────────────────────
  get chartDraft() {
    return this.data?.chartDraft ?? 0;
  }
  get chartSent() {
    return this.data?.chartSent ?? 0;
  }
  get chartAccepted() {
    return this.data?.chartAccepted ?? 0;
  }
  get chartRejected() {
    return this.data?.chartRejected ?? 0;
  }
  get chartExpired() {
    return this.data?.chartExpired ?? 0;
  }

  // ─── Chart bars via renderedCallback ──────────────────────
  renderedCallback() {
    if (!this.data) return;

    const bars = {
      draft: this.chartDraft,
      sent: this.chartSent,
      accepted: this.chartAccepted,
      rejected: this.chartRejected,
      expired: this.chartExpired
    };

    const max = Math.max(...Object.values(bars), 1);

    Object.entries(bars).forEach(([key, value]) => {
      const el = this.template.querySelector(`[data-bar="${key}"]`);
      if (el) {
        const height = Math.max((value / max) * 160, 4);
        el.style.height = `${height}px`;
      }
    });
  }
}
