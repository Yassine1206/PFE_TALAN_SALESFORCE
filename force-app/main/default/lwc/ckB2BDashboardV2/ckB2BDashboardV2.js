import { LightningElement, wire } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import ChartJsResource from "@salesforce/resourceUrl/ChartJs";
import getDashboardData from "@salesforce/apex/CkB2BDashboardController.getDashboardData";
import getAdvancedData from "@salesforce/apex/CkB2BDashboardController.getAdvancedData";
import getSection5Data from "@salesforce/apex/CkB2BDashboardController.getSection5Data";
import getInsightsData from "@salesforce/apex/CkB2BDashboardController.getInsightsData";
import getSection7Data from "@salesforce/apex/CkB2BDashboardController.getSection7Data";
import getThemePreference from "@salesforce/apex/CkThemeController.getThemePreference";
import { applyThemeToComponent } from "c/ckThemeUtils";

export default class CkB2BDashboardV2 extends LightningElement {
  // ═══════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════
  isLoading = true;
  hasError = false;
  data = null;

  // Chart.js state
  chartJsLoaded = false;
  chartsRendered = false;
  chartInstances = {};

  // Counter animation state
  countersAnimated = false;

  advancedData = null;
  advancedRendered = false;

  section5Data = null;
  section5Rendered = false;

  selectedDay = null;
  selectedDayData = null;

  insightsData = null;

  insightsLoading = false;

  section7Data = null;

  // ═══════════════════════════════════════════════════════════
  // WIRE
  // ═══════════════════════════════════════════════════════════
  @wire(getDashboardData)
  wiredDashboard({ error, data }) {
    if (data) {
      this.data = data;
      this.isLoading = false;
      this.hasError = false;
      // Reset chart render flag so charts re-render with fresh data
      this.chartsRendered = false;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("ckB2BDashboardV2 error:", error);
      this.isLoading = false;
      this.hasError = true;
    }
  }

  @wire(getAdvancedData)
  wiredAdvanced({ error, data }) {
    if (data) {
      this.advancedData = data;
      this.advancedRendered = false; // force re-render on data change
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("getAdvancedData error:", error);
    }
  }

  @wire(getSection5Data)
  wiredSection5({ error, data }) {
    if (data) {
      this.section5Data = data;
      this.section5Rendered = false;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("getSection5Data error:", error);
    }
  }
  @wire(getThemePreference)
  wiredTheme({ data, error }) {
    if (data) {
      this.applyTheme(data === "Dark");
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("getTheme error:", error);
    }
  }

  applyTheme(isDark) {
    if (isDark) {
      this.setAttribute("data-theme", "dark");
    } else {
      this.removeAttribute("data-theme");
    }
  }
  // ═══════════════════════════════════════════════════════════
  // VISIBILITY GETTERS
  // ═══════════════════════════════════════════════════════════
  get isLoading() {
    return !this.data || !this.data.account;
  }
  get showDashboard() {
    return !this.isLoading && !this.hasError && this.data != null;
  }

  get showCharts() {
    return this.showDashboard;
  }

  get hasSpendingData() {
    const cats = this.data?.spendingByCategory || [];
    return cats.length > 0 && cats.some((c) => (c.total || 0) > 0);
  }

  get showAdvanced() {
    return this.showDashboard && this.advancedData != null;
  }

  get heatmapTotalActivity() {
    const days = this.advancedData?.heatmap || [];
    return days.reduce((s, d) => s + (d.count || 0), 0);
  }

  get showSection5() {
    return this.showDashboard && this.section5Data != null;
  }

  get hasTopProducts() {
    return (this.section5Data?.topProducts || []).length > 0;
  }

  get hasNotifications() {
    return (this.section5Data?.notifications || []).length > 0;
  }

  get showSection6() {
    return this.showDashboard && this.insightsData != null;
  }

  get hasInsights() {
    return (this.insightsData?.insights || []).length > 0;
  }

  get showSection7() {
    return this.showDashboard && this.section7Data != null;
  }

  get hasRecommendations() {
    return (this.section7Data?.recommendedProducts || []).length > 0;
  }

  get hasUpcoming() {
    return (this.section7Data?.upcomingEvents || []).length > 0;
  }

  get isRecommendationsAiPowered() {
    return this.section7Data?.recommendationsAiPowered === true;
  }
  // Recommended getters ───
  get recommendedProducts() {
    return (this.section7Data?.recommendedProducts || []).map((p) => ({
      ...p,
      productUrl: `/TalFlowExpress/s/product/${p.productId}`,
      priceDisplay: this.formatCurrency(p.price || 0)
    }));
  }

  // ─── (8) Upcoming getters ───
  get upcomingCount() {
    return (this.section7Data?.upcomingEvents || []).length;
  }

  get upcomingEvents() {
    return (this.section7Data?.upcomingEvents || []).map((e) => {
      const isHigh = e.urgency === "high";
      return {
        ...e,
        isContract: e.icon === "contract",
        isQuote: e.icon === "quote",
        itemClass: isHigh
          ? "ck-upcoming-item ck-upcoming-item-high"
          : "ck-upcoming-item",
        iconClass: `ck-upcoming-icon ck-upcoming-icon-${e.icon}`,
        dateDisplay: this.formatUpcomingDate(e.date)
      };
    });
  }

  formatUpcomingDate(dateStr) {
    if (!dateStr) return "";
    const d = new Date(dateStr);
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }
  // ═══════════════════════════════════════════════════════════
  // HERO GETTERS
  // ═══════════════════════════════════════════════════════════
  get firstName() {
    return this.data?.firstName || "there";
  }

  get accountName() {
    return this.data?.accountName || "";
  }

  get memberSince() {
    return this.data?.memberSince || "";
  }

  get greeting() {
    const h = new Date().getHours();
    if (h < 12) return "Good morning";
    if (h < 18) return "Good afternoon";
    return "Good evening";
  }

  get todayBadge() {
    const d = new Date();
    return d
      .toLocaleDateString("en-US", {
        weekday: "short",
        month: "short",
        day: "numeric",
        year: "numeric"
      })
      .toUpperCase();
  }

  get heroQuickStats() {
    const s = this.data?.heroStats || {};
    return {
      pendingQuotes: s.pendingQuotes ?? 0,
      activeContracts: s.activeContracts ?? 0,
      ytdSpend: this.formatCurrency(s.ytdSpend ?? 0)
    };
  }

  // ═══════════════════════════════════════════════════════════
  // METRICS GETTERS
  // ═══════════════════════════════════════════════════════════
  get metrics() {
    return (this.data?.metrics || []).map((m) => {
      const isPositive = m.changeDirection === "positive";
      const formattedValue = this.formatMetricValue(m.value, m.format);
      const formattedPrevious = this.formatMetricValue(m.previous, m.format);
      const changeAbs = Math.abs(m.change || 0);
      const arrow = (m.change || 0) >= 0 ? "▲" : "▼";

      return {
        ...m,
        displayValue: formattedValue,
        displayPrevious: formattedPrevious,
        changeClass: isPositive
          ? "ck-metric-change-positive"
          : "ck-metric-change-negative",
        arrowText: `${arrow} ${changeAbs}%`
      };
    });
  }

  // ═══════════════════════════════════════════════════════════
  // CHART GETTERS
  // ═══════════════════════════════════════════════════════════
  get revenueTotalFormatted() {
    const trend = this.data?.revenueTrend || [];
    const total = trend.reduce((sum, m) => sum + (m.value || 0), 0);
    return this.formatCurrency(total);
  }

  get pipelineTotal() {
    return this.data?.quotesPipeline?.total ?? 0;
  }

  get pipelineConversion() {
    return this.data?.quotesPipeline?.conversion ?? 0;
  }
  get geoUserCity() {
    return this.section5Data?.geo?.userCity || "Unknown";
  }

  get geoUserCountry() {
    return this.section5Data?.geo?.userCountry || "Unknown";
  }

  get geoTotalB2B() {
    return this.section5Data?.geo?.totalB2B ?? 0;
  }

  get geoSameCountry() {
    return this.section5Data?.geo?.sameCountry ?? 0;
  }

  get topProducts() {
    return (this.section5Data?.topProducts || []).map((p) => ({
      ...p,
      displaySpent: this.formatCurrency(p.totalSpent || 0)
    }));
  }

  get notifications() {
    return (this.section5Data?.notifications || []).map((n, i) => ({
      ...n,
      id: `notif-${i}`,
      cardClass:
        n.priority === "high" ? "ck-notif-item ck-notif-high" : "ck-notif-item",
      iconClass: `ck-notif-icon ck-notif-icon-${n.iconType}`
    }));
  }

  get notifCount() {
    return (this.section5Data?.notifications || []).length;
  }

  get mapMarkers() {
    const geo = this.section5Data?.geo;
    if (!geo) return [];

    return [
      {
        location: {
          Latitude: geo.userLat || 36.8463,
          Longitude: geo.userLng || 10.1932
        },
        title: geo.userCity || "Your Location",
        description: `${geo.userCountry || ""} — TalFlow B2B Customer`,
        icon: "standard:account"
      }
    ];
  }
  get geoSameCity() {
    return this.section5Data?.geo?.sameCity ?? 0;
  }
  get mapCenter() {
    const geo = this.section5Data?.geo;
    return {
      location: {
        Latitude: geo?.userLat || 36.8463,
        Longitude: geo?.userLng || 10.1932
      }
    };
  }

  get selectedDayFormatted() {
    if (!this.selectedDayData) return "";
    const d = new Date(this.selectedDayData.date);
    return d.toLocaleDateString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric"
    });
  }

  get selectedDayHasActivities() {
    return (this.selectedDayData?.activities || []).length > 0;
  }

  get selectedDayActivities() {
    const acts = this.selectedDayData?.activities || [];
    return acts.map((a) => {
      const isQuote = a.type === "quote";
      const status = a.status || "Unknown";
      const statusLower = status.toLowerCase().replace(/\s+/g, "-");
      return {
        ...a,
        isQuote: isQuote,
        displayAmount: this.formatCurrency(a.amount || 0),
        iconClass: isQuote
          ? "ck-contrib-icon ck-contrib-icon-quote"
          : "ck-contrib-icon ck-contrib-icon-order",
        itemClass: "ck-contrib-item",
        statusClass: `ck-contrib-status ck-contrib-status-${statusLower}`
      };
    });
  }

  // ── Tier ──
  get tierName() {
    return this.insightsData?.tier || "Bronze";
  }

  get tierCurrentName() {
    return this.section7Data?.tier?.currentTier || "Bronze";
  }

  get tierBadgeClass() {
    const name = (
      this.section7Data?.tier?.currentTier || "Bronze"
    ).toLowerCase();
    return `ck-tier-badge ck-tier-badge-${name}`;
  }

  get tierNextName() {
    return this.section7Data?.tier?.nextTier || "";
  }

  get tierHasNext() {
    return !!this.section7Data?.tier?.nextTier;
  }

  get tierProgressPercent() {
    return this.section7Data?.tier?.progress ?? 0;
  }

  get tierProgressDisplay() {
    const ytd = this.section7Data?.tier?.ytdSpend ?? 0;
    const limit = this.section7Data?.tier?.nextTierLimit ?? 0;
    return `${this.formatCurrency(ytd)} / ${this.formatCurrency(limit)}`;
  }

  get tierToNextDisplay() {
    const toNext = this.section7Data?.tier?.toNextTier ?? 0;
    return this.formatCurrency(toNext);
  }

  get tierBenefits() {
    return this.section7Data?.tier?.benefits || [];
  }
  // ── Health Score ──
  get healthScore() {
    return this.insightsData?.healthScore?.score ?? 0;
  }

  get healthRating() {
    return this.insightsData?.healthScore?.rating || "Building";
  }

  get healthRatingClass() {
    const rating = (
      this.insightsData?.healthScore?.rating || "Building"
    ).toLowerCase();
    return `ck-health-badge ck-health-badge-${rating}`;
  }

  get healthGaugeColor() {
    const score = this.insightsData?.healthScore?.score ?? 0;
    if (score >= 80) return "#1D9E75"; // green
    if (score >= 60) return "#FF6B1A"; // orange
    if (score >= 40) return "#FFB347"; // light orange
    return "#E24B4A"; // red
  }

  get healthGaugeDashArray() {
    // Circle r=80 → circumference = 2 * π * 80 ≈ 502.65
    const score = this.insightsData?.healthScore?.score ?? 0;
    const circumference = 502.65;
    const filled = (score / 100) * circumference;
    return `${filled} ${circumference}`;
  }

  get healthBreakdown() {
    const items = this.insightsData?.healthScore?.breakdown || [];
    return items.map((item) => {
      const percent = item.max > 0 ? (item.score / item.max) * 100 : 0;
      let color = "#1D9E75";
      if (percent < 50) color = "#E24B4A";
      else if (percent < 75) color = "#FF6B1A";
      return {
        ...item,
        percent: Math.round(percent),
        color: color
      };
    });
  }

  // ── Cost Savings ──
  get costSavingsTotal() {
    const total = this.insightsData?.costSavings?.totalSaved ?? 0;
    return this.formatCurrency(total);
  }

  get costSavingsPct() {
    return this.insightsData?.costSavings?.savedPct ?? 0;
  }

  get costSavingsUnits() {
    return this.insightsData?.costSavings?.unitsBought ?? 0;
  }

  // ── Forecast ──
  get forecastNextMonth() {
    const val = this.insightsData?.forecast?.nextMonthForecast ?? 0;
    return this.formatCurrency(val);
  }

  get forecastQ3() {
    const val = this.insightsData?.forecast?.q3Forecast ?? 0;
    return this.formatCurrency(val);
  }

  get forecastConfidence() {
    return this.insightsData?.forecast?.confidence || "low";
  }

  // ── AI Insights ──
  get insightsCount() {
    return (this.insightsData?.insights || []).length;
  }

  get aiInsights() {
    const list = this.insightsData?.insights || [];
    return list.map((ins) => {
      const icon = ins.icon || "info";
      const isTrophy = icon === "trophy";
      const isAlert = icon === "alert";
      const colorMap = {
        trophy: "ck-insight-icon-orange",
        alert: "ck-insight-icon-red",
        "trending-up": "ck-insight-icon-green"
      };
      return {
        ...ins,
        isTrophy: isTrophy,
        isAlert: isAlert,
        cardClass: isAlert
          ? "ck-insight-item ck-insight-item-alert"
          : "ck-insight-item",
        iconClass: `ck-insight-icon ${colorMap[icon] || "ck-insight-icon-orange"}`
      };
    });
  }

  get isAiPowered() {
    return this.insightsData?.aiPowered === true;
  }

  // ═══════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════

  renderedCallback() {
    if (!this.data || !this.showDashboard) return;

    // ─── Phase 1: Counter animations ───
    if (!this.countersAnimated) {
      this.animateCounters();
      this.countersAnimated = true;
    }

    // ─── Phase 2: Chart.js (async load) ───
    if (!this.chartJsLoaded) {
      loadScript(this, ChartJsResource)
        .then(() => {
          this.chartJsLoaded = true;
          this.renderAllCharts();
          // After Chart.js loads, also try to render advanced
          // (in case advancedData was already there but blocked by early return)
          if (this.advancedData && !this.advancedRendered) {
            this.renderAdvanced();
            this.advancedRendered = true;
          }
        })
        .catch((err) => {
          // eslint-disable-next-line no-console
          console.error("Chart.js failed to load:", err);
        });
    }
    if (this.section5Data && !this.section5Rendered) {
      this.renderSection5();
      this.section5Rendered = true;
    } else if (!this.chartsRendered) {
      this.renderAllCharts();
    }

    // ─── Phase 3: Advanced rendering (heatmap) ───
    // Independent of Chart.js — uses pure HTML/SVG
    if (this.advancedData && !this.advancedRendered) {
      this.renderAdvanced();
      this.advancedRendered = true;
    }
    if (this.insightsData) {
      this.applyHealthBars();
    }
  }
  connectedCallback() {
    applyThemeToComponent(this);
    this.loadInsightsData();
    this.loadSection7Data();
  }
  disconnectedCallback() {
    Object.values(this.chartInstances).forEach((c) => {
      try {
        c?.destroy();
      } catch (e) {
        // ignore
      }
    });
    this.chartInstances = {};
  }

  loadSection7Data() {
    getSection7Data()
      .then((result) => {
        this.section7Data = result;
        // Apply tier progress bar after render
        setTimeout(() => this.applyTierProgressBar(), 50);
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("getSection7Data error:", error);
      });
  }

  applyTierProgressBar() {
    const fill = this.template.querySelector(".ck-tier-progress-fill");
    if (fill) {
      const progress = fill.dataset.progress || 0;
      fill.style.width = progress + "%";
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CHART RENDERING
  // ═══════════════════════════════════════════════════════════
  renderAllCharts() {
    if (!window.Chart) return;
    this.renderRevenueChart();
    if (this.hasSpendingData) {
      this.renderDonutChart();
    }
    this.renderPipelineChart();
    this.chartsRendered = true;
  }

  // ─── Revenue Line Chart with gradient fill ─────────────────
  renderRevenueChart() {
    const canvas = this.template.querySelector('canvas[data-chart="revenue"]');
    if (!canvas) return;

    if (this.chartInstances.revenue) {
      this.chartInstances.revenue.destroy();
    }

    const ctx = canvas.getContext("2d");
    const trend = this.data?.revenueTrend || [];
    const labels = trend.map((m) => m.label);
    const values = trend.map((m) => m.value || 0);

    // Vertical gradient fill: orange → transparent
    const gradient = ctx.createLinearGradient(0, 0, 0, 280);
    gradient.addColorStop(0, "rgba(255, 107, 26, 0.35)");
    gradient.addColorStop(1, "rgba(255, 107, 26, 0.0)");

    this.chartInstances.revenue = new window.Chart(ctx, {
      type: "line",
      data: {
        labels: labels,
        datasets: [
          {
            label: "Revenue",
            data: values,
            borderColor: "#FF6B1A",
            borderWidth: 2.5,
            tension: 0.4,
            fill: true,
            backgroundColor: gradient,
            pointBackgroundColor: "#0A1628",
            pointBorderColor: "#FFFFFF",
            pointBorderWidth: 2,
            pointRadius: 0,
            pointHoverRadius: 6,
            pointHoverBackgroundColor: "#FF6B1A",
            pointHoverBorderColor: "#FFFFFF",
            pointHoverBorderWidth: 2
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { intersect: false, mode: "index" },
        animation: { duration: 800, easing: "easeOutCubic" },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: "#0A1628",
            titleColor: "#FFFFFF",
            bodyColor: "#FFFFFF",
            padding: 10,
            cornerRadius: 8,
            displayColors: false,
            titleFont: { size: 11, weight: "700", family: "Arial" },
            bodyFont: { size: 13, weight: "700", family: "Arial" },
            callbacks: {
              label: (ctxItem) =>
                "$" +
                ctxItem.parsed.y.toLocaleString("en-US", {
                  maximumFractionDigits: 0
                })
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              color: "#868E96",
              font: { size: 10, family: "Arial" }
            },
            border: { display: false }
          },
          y: {
            grid: { color: "#F1F3F5" },
            ticks: {
              color: "#868E96",
              font: { size: 10, family: "Arial" },
              callback: (val) => "$" + (val >= 1000 ? val / 1000 + "k" : val)
            },
            border: { display: false },
            beginAtZero: true
          }
        }
      }
    });
  }

  // ─── Donut Chart with center text ──────────────────────────
  renderDonutChart() {
    const canvas = this.template.querySelector('canvas[data-chart="donut"]');
    if (!canvas) return;

    if (this.chartInstances.donut) {
      this.chartInstances.donut.destroy();
    }

    const ctx = canvas.getContext("2d");
    const cats = this.data?.spendingByCategory || [];
    const colors = ["#FF6B1A", "#0A1628", "#1D9E75", "#1971C2", "#E24B4A"];
    const labels = cats.map((c) => c.category || "Unknown");
    const values = cats.map((c) => c.total || 0);
    const total = values.reduce((s, v) => s + v, 0);

    this.chartInstances.donut = new window.Chart(ctx, {
      type: "doughnut",
      data: {
        labels: labels,
        datasets: [
          {
            data: values,
            backgroundColor: colors.slice(0, values.length),
            borderColor: "#FFFFFF",
            borderWidth: 3,
            hoverOffset: 8
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: "65%",
        animation: { animateRotate: true, animateScale: false, duration: 900 },
        plugins: {
          legend: {
            position: "right",
            align: "center",
            labels: {
              color: "#0A1628",
              font: { size: 11, weight: "600", family: "Arial" },
              padding: 10,
              boxWidth: 10,
              boxHeight: 10,
              usePointStyle: true,
              pointStyle: "circle"
            }
          },
          tooltip: {
            backgroundColor: "#0A1628",
            titleColor: "#FFFFFF",
            bodyColor: "#FFFFFF",
            padding: 10,
            cornerRadius: 8,
            callbacks: {
              label: (ctxItem) => {
                const val = ctxItem.parsed;
                const pct = total > 0 ? ((val / total) * 100).toFixed(1) : "0";
                return (
                  ctxItem.label +
                  ": $" +
                  val.toLocaleString("en-US", { maximumFractionDigits: 0 }) +
                  " (" +
                  pct +
                  "%)"
                );
              }
            }
          }
        }
      },
      plugins: [
        {
          id: "centerText",
          beforeDraw: (chart) => {
            const { ctx: c, chartArea } = chart;
            if (!chartArea) return;
            const cx = (chartArea.left + chartArea.right) / 2;
            const cy = (chartArea.top + chartArea.bottom) / 2;

            c.save();
            c.font = "bold 18px Arial";
            c.fillStyle = "#0A1628";
            c.textAlign = "center";
            c.textBaseline = "middle";
            const totalStr =
              "$" +
              (total >= 1000
                ? (total / 1000).toFixed(1) + "k"
                : total.toFixed(0));
            c.fillText(totalStr, cx, cy - 6);

            c.font = "700 9px Arial";
            c.fillStyle = "#868E96";
            c.fillText("TOTAL", cx, cy + 12);
            c.restore();
          }
        }
      ]
    });
  }

  // ─── Pipeline Bar Chart with values on top ─────────────────
  renderPipelineChart() {
    const canvas = this.template.querySelector('canvas[data-chart="pipeline"]');
    if (!canvas) return;

    if (this.chartInstances.pipeline) {
      this.chartInstances.pipeline.destroy();
    }

    const ctx = canvas.getContext("2d");
    const p = this.data?.quotesPipeline || {};
    const labels = ["Draft", "Sent", "Accepted", "Rejected", "Expired"];
    const values = [
      p.draft || 0,
      p.sent || 0,
      p.accepted || 0,
      p.rejected || 0,
      p.expired || 0
    ];
    const colors = ["#868E96", "#1971C2", "#1D9E75", "#E24B4A", "#FF6B1A"];

    this.chartInstances.pipeline = new window.Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [
          {
            data: values,
            backgroundColor: colors,
            borderRadius: 8,
            borderSkipped: false,
            barThickness: 50,
            maxBarThickness: 70
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 800, easing: "easeOutQuart" },
        layout: { padding: { top: 24 } },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: "#0A1628",
            titleColor: "#FFFFFF",
            bodyColor: "#FFFFFF",
            padding: 10,
            cornerRadius: 8,
            displayColors: false,
            callbacks: {
              label: (ctxItem) => {
                const v = ctxItem.parsed.y;
                return v + " quote" + (v !== 1 ? "s" : "");
              }
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              color: "#0A1628",
              font: { size: 11, weight: "600", family: "Arial" }
            },
            border: { display: false }
          },
          y: {
            grid: { color: "#F1F3F5" },
            ticks: {
              color: "#868E96",
              font: { size: 10, family: "Arial" },
              stepSize: 1,
              precision: 0
            },
            border: { display: false },
            beginAtZero: true
          }
        }
      },
      plugins: [
        {
          id: "valueOnTop",
          afterDatasetsDraw: (chart) => {
            const { ctx: c } = chart;
            chart.data.datasets[0].data.forEach((value, i) => {
              const meta = chart.getDatasetMeta(0);
              const bar = meta.data[i];
              if (!bar || value === 0) return;
              c.save();
              c.font = "bold 14px Arial";
              c.fillStyle = "#0A1628";
              c.textAlign = "center";
              c.fillText(value, bar.x, bar.y - 8);
              c.restore();
            });
          }
        }
      ]
    });
  }

  // ═══════════════════════════════════════════════════════════
  // COUNTER ANIMATIONS
  // ═══════════════════════════════════════════════════════════
  animateCounters() {
    const elements = this.template.querySelectorAll("[data-counter]");
    elements.forEach((el) => {
      const target = parseFloat(el.dataset.counter) || 0;
      const format = el.dataset.format || "number";
      this.animateValue(el, 0, target, 1000, format);
    });
  }

  animateValue(el, start, end, duration, format) {
    const startTime = performance.now();
    const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

    const tick = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased = easeOutCubic(progress);
      const value = start + (end - start) * eased;
      el.textContent = this.formatMetricValue(value, format);
      if (progress < 1) {
        // eslint-disable-next-line no-undef
        requestAnimationFrame(tick);
      } else {
        el.textContent = this.formatMetricValue(end, format);
      }
    };
    // eslint-disable-next-line no-undef
    requestAnimationFrame(tick);
  }

  // ═══════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════
  handleRequestQuote() {
    window.location.href = "/TalFlowExpress/s/request-quote";
  }

  // ═══════════════════════════════════════════════════════════
  // FORMATTERS
  // ═══════════════════════════════════════════════════════════
  formatCurrency(val) {
    if (val == null || val === 0) return "$0";
    if (val >= 1000) return "$" + (val / 1000).toFixed(1) + "k";
    return "$" + Math.round(val);
  }

  formatMetricValue(val, format) {
    if (val == null) val = 0;
    if (format === "currency") {
      if (val >= 1000) return "$" + (val / 1000).toFixed(1) + "k";
      return "$" + Math.round(val);
    }
    if (format === "days") {
      return val.toFixed(1) + "d";
    }
    return Math.round(val).toString();
  }

  // ═══════════════════════════════════════════════════════════
  // ADVANCED RENDERING — Heatmap
  // ═══════════════════════════════════════════════════════════

  renderAdvanced() {
    this.renderHeatmap();
  }

  // ─── HEATMAP — GitHub-style HTML grid ─────────────────────
  renderHeatmap() {
    const wrapper = this.template.querySelector(".ck-heatmap-wrapper");
    if (!wrapper) return;

    const days = this.advancedData?.heatmap || [];
    if (days.length === 0) {
      wrapper.innerHTML =
        '<div class="ck-chart-empty"><p>No activity yet</p></div>';
      return;
    }

    const maxCount = Math.max(...days.map((d) => d.count || 0), 1);

    const getLevel = (count) => {
      if (count === 0) return 0;
      const ratio = count / maxCount;
      if (ratio <= 0.25) return 1;
      if (ratio <= 0.5) return 2;
      if (ratio <= 0.75) return 3;
      return 4;
    };

    const firstDay = new Date(days[0].date);
    const padding = firstDay.getDay();

    const cells = [];
    for (let i = 0; i < padding; i++) {
      cells.push({ empty: true });
    }
    days.forEach((d) => {
      cells.push({
        date: d.date,
        count: d.count || 0,
        level: getLevel(d.count || 0),
        empty: false
      });
    });

    const cols = [];
    for (let i = 0; i < cells.length; i += 7) {
      cols.push(cells.slice(i, i + 7));
    }

    const monthNames = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    const monthLabels = [];
    let lastMonth = -1;
    cols.forEach((col, colIdx) => {
      const firstNonEmpty = col.find((c) => !c.empty);
      if (firstNonEmpty) {
        const m = new Date(firstNonEmpty.date).getMonth();
        if (m !== lastMonth) {
          monthLabels.push({ col: colIdx, label: monthNames[m] });
          lastMonth = m;
        }
      }
    });

    let html = '<div class="ck-heatmap">';

    // Month labels
    html += '<div class="ck-heatmap-months">';
    html += '<div class="ck-heatmap-day-spacer"></div>';
    cols.forEach((_, colIdx) => {
      const lbl = monthLabels.find((m) => m.col === colIdx);
      html += `<div class="ck-heatmap-month-cell">${lbl ? lbl.label : ""}</div>`;
    });
    html += "</div>";

    // Body
    html += '<div class="ck-heatmap-body">';

    const dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    html += '<div class="ck-heatmap-days">';
    dayLabels.forEach((d, i) => {
      // Show only Mon, Wed, Fri (i = 1, 3, 5) — others empty for spacing
      const showLabel = i === 1 || i === 3 || i === 5;
      html += `<div class="ck-heatmap-day-label">${showLabel ? d : ""}</div>`;
    });
    html += "</div>";

    html += '<div class="ck-heatmap-grid">';
    for (let row = 0; row < 7; row++) {
      html += '<div class="ck-heatmap-row">';
      cols.forEach((col) => {
        const cell = col[row];
        if (!cell || cell.empty) {
          html += '<div class="ck-heat-cell ck-heat-empty"></div>';
        } else {
          const tooltip = `${cell.date} — ${cell.count} ${cell.count === 1 ? "activity" : "activities"} · click for details`;
          html += `<div class="ck-heat-cell ck-heat-level-${cell.level} ck-heat-clickable" 
                              data-date="${cell.date}" 
                              title="${tooltip}"></div>`;
        }
      });
      html += "</div>";
    }
    html += "</div>"; // /grid
    html += "</div>"; // /body
    html += "</div>"; // /heatmap

    wrapper.innerHTML = html;

    // ─── Add click event listeners on each clickable cell ───
    const clickables = wrapper.querySelectorAll(".ck-heat-clickable");
    clickables.forEach((cell) => {
      cell.addEventListener("click", (event) => {
        const dateStr = event.currentTarget.dataset.date;
        this.handleHeatmapCellClick(dateStr);
      });
    });
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION 5 RENDERING — World Map + Notification icons
  // ═══════════════════════════════════════════════════════════

  renderSection5() {
    this.renderNotificationIcons();
  }

  // ─── Notification Icons (SVG by type) ────────────────────
  renderNotificationIcons() {
    const iconsByType = {
      quote: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>`,
      contract: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`,
      order: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 1.99-1.79l1.54-8.89H6"/></svg>`,
      alert: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>`
    };

    const iconWrappers = this.template.querySelectorAll(
      ".ck-notif-icon[data-icon-type]"
    );
    iconWrappers.forEach((el) => {
      const type = el.dataset.iconType;
      el.innerHTML = iconsByType[type] || iconsByType.alert;
    });
  }

  handleCloseContribPanel() {
    this.selectedDay = null;
    this.selectedDayData = null;
  }
  handleHeatmapCellClick(dateStr) {
    const days = this.advancedData?.heatmap || [];
    const dayData = days.find((d) => d.date === dateStr);
    if (dayData) {
      this.selectedDay = dateStr;
      this.selectedDayData = dayData;
    }
  }
  applyHealthBars() {
    if (!this.insightsData) return;
    const bars = this.template.querySelectorAll(".ck-health-item-bar-fill");
    bars.forEach((bar) => {
      const percent = bar.dataset.percent || 0;
      const color = bar.dataset.color || "#1D9E75";
      bar.style.width = percent + "%";
      bar.style.background = color;
    });
  }

  loadInsightsData() {
    this.insightsLoading = true;
    getInsightsData()
      .then((result) => {
        this.insightsData = result;
        this.insightsLoading = false;
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("getInsightsData error:", error);
        this.insightsData = null;
        this.insightsLoading = false;
      });
  }
}
