import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getThemePreference from "@salesforce/apex/CkThemeController.getThemePreference";
import setThemePreference from "@salesforce/apex/CkThemeController.setThemePreference";
import getMyNotifications from "@salesforce/apex/CkNotificationController.getMyNotifications";
import getUnreadCount from "@salesforce/apex/CkNotificationController.getUnreadCount";
import markAsRead from "@salesforce/apex/CkNotificationController.markAsRead";
import markAllAsRead from "@salesforce/apex/CkNotificationController.markAllAsRead";

export default class CkB2BSidebar extends LightningElement {
  // ═══════════════════════════════════════════════════════════
  //   USER DATA (à remplacer par @wire vers Apex plus tard)
  // ═══════════════════════════════════════════════════════════
  userName = "chiheb zaddem";
  accountName = "ENSI";
  userEmail = "chihebeddine.zaddem@talan.com";
  avatarUrl = null;
  quotesCount = 1;

  isDarkMode = false;

  // ═══════════════════════════════════════════════════════════
  //   NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════
  notifications = [];
  unreadCount = 0;
  isNotifOpen = false;
  wiredNotifResult;
  wiredCountResult;
  refreshInterval;

  @wire(getMyNotifications, { maxResults: 15 })
  wiredNotifications(result) {
    this.wiredNotifResult = result;
    if (result.data) {
      this.notifications = result.data.map((n) => ({
        ...n,
        isUnread: !n.Is_Read__c,
        typeClass: this.getTypeClass(n.Type__c),
        typeIcon: this.getTypeIcon(n.Type__c),
        relativeTime: this.getRelativeTime(n.CreatedDate),
        rowClass: n.Is_Read__c ? "ck-notif-row read" : "ck-notif-row unread"
      }));
    }
  }

  @wire(getUnreadCount)
  wiredCount(result) {
    this.wiredCountResult = result;
    if (result.data !== undefined) {
      this.unreadCount = result.data;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //   GETTERS
  // ═══════════════════════════════════════════════════════════

  get userInitials() {
    if (!this.userName) return "?";
    const parts = this.userName.trim().split(" ");
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return this.userName.substring(0, 2).toUpperCase();
  }

  get hasAvatar() {
    return !!this.avatarUrl;
  }

  get hasQuotesBadge() {
    return this.quotesCount && this.quotesCount > 0;
  }

  get hasUnreadNotifs() {
    return this.unreadCount > 0;
  }

  get displayUnreadCount() {
    return this.unreadCount > 9 ? "9+" : this.unreadCount;
  }

  get hasNotifications() {
    return this.notifications && this.notifications.length > 0;
  }

  get notifDropdownClass() {
    return this.isNotifOpen
      ? "ck-notif-dropdown ck-notif-dropdown-open"
      : "ck-notif-dropdown";
  }

  // Active link detection
  get dashboardClass() {
    return this.isActive("b2b-dashboard")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get catalogClass() {
    return this.isActive("b2b-catalog")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get quotesClass() {
    return this.isActive("my-quotes")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get contractsClass() {
    return this.isActive("my-contracts")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get profileClass() {
    return this.isActive("edit-profile")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get ordersClass() {
    return this.isActive("my-orders-b2b")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  get invoicesClass() {
    return this.isActive("my-invoices")
      ? "ck-nav-link ck-nav-active"
      : "ck-nav-link";
  }

  isActive(path) {
    try {
      return window.location.pathname.includes(path);
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //   LIFECYCLE
  // ═══════════════════════════════════════════════════════════

  connectedCallback() {
    this.injectGlobalStyles();
    this.loadTheme();

    // Auto-refresh notifications every 30s
    this.refreshInterval = setInterval(() => {
      this.refreshNotifs();
    }, 30000);
  }

  disconnectedCallback() {
    if (this.refreshInterval) clearInterval(this.refreshInterval);
    document.removeEventListener("click", this.handleOutsideClick);
  }

  // ═══════════════════════════════════════════════════════════
  //   NOTIFICATIONS HANDLERS
  // ═══════════════════════════════════════════════════════════

  toggleNotifications(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isNotifOpen = !this.isNotifOpen;

    if (this.isNotifOpen) {
      setTimeout(() => {
        document.addEventListener("click", this.handleOutsideClick);
      }, 0);
    } else {
      document.removeEventListener("click", this.handleOutsideClick);
    }
  }

  handleOutsideClick = (event) => {
    const wrapper = this.template.querySelector(".ck-notif-wrapper");
    if (wrapper && !wrapper.contains(event.target)) {
      this.isNotifOpen = false;
      document.removeEventListener("click", this.handleOutsideClick);
    }
  };

  async handleNotificationClick(event) {
    const notifId = event.currentTarget.dataset.id;
    const actionUrl = event.currentTarget.dataset.url;

    try {
      await markAsRead({ notificationId: notifId });
      await this.refreshNotifs();
    } catch (error) {
      console.error("markAsRead error:", error);
    }

    if (actionUrl && actionUrl !== "null" && actionUrl !== "undefined") {
      this.isNotifOpen = false;
      window.location.href = actionUrl;
    }
  }

  async handleMarkAllRead(event) {
    event.preventDefault();
    event.stopPropagation();

    try {
      await markAllAsRead();
      await this.refreshNotifs();
    } catch (error) {
      console.error("markAllAsRead error:", error);
    }
  }

  async refreshNotifs() {
    await Promise.all([
      refreshApex(this.wiredNotifResult),
      refreshApex(this.wiredCountResult)
    ]);
  }

  getTypeClass(type) {
    switch (type) {
      case "Success":
        return "ck-notif-icon-success";
      case "Warning":
        return "ck-notif-icon-warning";
      case "Alert":
        return "ck-notif-icon-alert";
      default:
        return "ck-notif-icon-info";
    }
  }

  getTypeIcon(type) {
    switch (type) {
      case "Success":
        return "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z";
      case "Warning":
        return "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z";
      case "Alert":
        return "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z";
      default:
        return "M11 17h2v-6h-2v6zm1-15C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zM11 9h2V7h-2v2z";
    }
  }

  getRelativeTime(dateStr) {
    if (!dateStr) return "";
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return "Just now";
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  }

  // ═══════════════════════════════════════════════════════════
  //   THEME (unchanged)
  // ═══════════════════════════════════════════════════════════

  loadTheme() {
    getThemePreference()
      .then((theme) => {
        this.isDarkMode = theme === "Dark";
        this.applyTheme();
      })
      .catch((error) => {
        console.error("loadTheme error:", error);
      });
  }

  handleToggleTheme() {
    this.isDarkMode = !this.isDarkMode;
    const newTheme = this.isDarkMode ? "Dark" : "Light";

    setThemePreference({ theme: newTheme })
      .then(() => {
        location.reload();
      })
      .catch((err) => {
        console.error("setTheme error:", err);
      });
  }

  applyTheme() {
    if (this.isDarkMode) {
      document.documentElement.setAttribute("data-theme", "dark");
    } else {
      document.documentElement.removeAttribute("data-theme");
    }
  }

  get themeToggleClass() {
    return this.isDarkMode ? "ck-theme-toggle ck-theme-on" : "ck-theme-toggle";
  }

  get themeIconLabel() {
    return this.isDarkMode ? "🌙 Dark" : "☀️ Light";
  }

  // ═══════════════════════════════════════════════════════════
  //   GLOBAL CSS (unchanged)
  // ═══════════════════════════════════════════════════════════

  injectGlobalStyles() {
    if (document.getElementById("ck-b2b-global-styles")) return;

    const style = document.createElement("style");
    style.id = "ck-b2b-global-styles";
    style.textContent = `
            .siteforceContentArea,
            .cContentLayout,
            .siteforceThemeLayoutStarter .mainContentMark {
                margin-left: 240px !important;
            }
            .slds-col,
            .slds-grid > div,
            [class*="slds-size_"],
            [class*="slds-max-medium-size_"],
            [class*="slds-medium-size_"],
            [class*="slds-large-size_"] {
                min-height: 0 !important;
                height: auto !important;
            }
            c-ck-b2-b-dashboard-v2 {
                display: block !important;
                height: auto !important;
                min-height: 0 !important;
            }
            .siteforceContentArea,
            .cContentLayout,
            .siteforceThemeLayoutStarter .mainContentMark,
            .comm-page-b2b-dashboard,
            .comm-layout-section,
            .comm-layout-column,
            .siteforceContentArea > div,
            .cContentLayout > div {
                min-height: 0 !important;
                height: auto !important;
            }
            .forceCommunitySection .cb-section_row,
            .cb-section_row,
            .cb-section_row.slds-grid,
            .cb-section_row.slds-wrap,
            .cb-section_row.slds-large-nowrap {
                min-height: 0 !important;
                height: auto !important;
            }
            .forceCommunitySection .cb-section_column,
            .cb-section_column,
            .cb-section_column.slds-size_12-of-12,
            .cb-section_column.slds-max-medium-size_12-of-12 {
                min-height: 0 !important;
                height: auto !important;
                align-self: flex-start !important;
            }
            .forceCommunitySection,
            .cb-section {
                min-height: 0 !important;
                height: auto !important;
            }
            .siteforceThemeLayoutStarter .siteforceServiceHeader,
            .siteforceThemeLayoutStarter .navContainer,
            header.cTalflowHeader,
            .cTalflowHeader,
            .talflowHeaderContainer {
                display: none !important;
            }
            footer.cTalflowFooter,
            .cTalflowFooter,
            .talflowFooterContainer,
            .siteforceThemeLayoutStarter footer {
                display: none !important;
            }
            body, html {
                background: #f8f9fa !important;
            }
            .slds-grid_align-stretch,
            .slds-grid_vertical-align-center,
            .slds-grid_vertical-stretch {
                align-items: flex-start !important;
            }
        `;
    document.head.appendChild(style);
  }

  // Sign out handler (placeholder)
  handleSignOut(event) {
    event.preventDefault();
    window.location.href = "/secur/logout.jsp";
  }
}
