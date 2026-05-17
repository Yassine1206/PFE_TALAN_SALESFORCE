import { LightningElement, wire, track } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import getMyNotifications from "@salesforce/apex/CkNotificationController.getMyNotifications";
import getUnreadCount from "@salesforce/apex/CkNotificationController.getUnreadCount";
import markAsRead from "@salesforce/apex/CkNotificationController.markAsRead";
import markAllAsRead from "@salesforce/apex/CkNotificationController.markAllAsRead";

export default class CkNotificationBell extends NavigationMixin(
  LightningElement
) {
  @track notifications = [];
  @track unreadCount = 0;
  @track isOpen = false;
  @track loading = false;

  wiredNotificationsResult;
  wiredCountResult;

  // Auto-refresh every 30 seconds
  refreshInterval;

  @wire(getMyNotifications, { maxResults: 15 })
  wiredNotifications(result) {
    this.wiredNotificationsResult = result;
    if (result.data) {
      this.notifications = result.data.map((n) => ({
        ...n,
        typeClass: this.getTypeClass(n.Type__c),
        typeIcon: this.getTypeIcon(n.Type__c),
        relativeTime: this.getRelativeTime(n.CreatedDate),
        rowClass: n.Is_Read__c ? "notif-row read" : "notif-row unread"
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

  connectedCallback() {
    // Refresh data every 30 seconds for real-time feel
    this.refreshInterval = setInterval(() => {
      this.refreshData();
    }, 30000);
  }

  disconnectedCallback() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
  }

  get hasUnread() {
    return this.unreadCount > 0;
  }

  get displayCount() {
    return this.unreadCount > 9 ? "9+" : this.unreadCount;
  }

  get hasNotifications() {
    return this.notifications && this.notifications.length > 0;
  }

  get dropdownClass() {
    return this.isOpen ? "notif-dropdown open" : "notif-dropdown";
  }

  toggleDropdown(event) {
    event.stopPropagation();
    this.isOpen = !this.isOpen;

    if (this.isOpen) {
      // Close when clicking outside
      setTimeout(() => {
        document.addEventListener("click", this.handleOutsideClick);
      }, 0);
    }
  }

  handleOutsideClick = (event) => {
    if (
      !this.template.querySelector(".notif-container").contains(event.target)
    ) {
      this.isOpen = false;
      document.removeEventListener("click", this.handleOutsideClick);
    }
  };

  async handleNotificationClick(event) {
    const notifId = event.currentTarget.dataset.id;
    const actionUrl = event.currentTarget.dataset.url;

    // Mark as read
    try {
      await markAsRead({ notificationId: notifId });
      await this.refreshData();
    } catch (error) {
      console.error("Failed to mark as read:", error);
    }

    // Navigate if URL provided
    if (actionUrl && actionUrl !== "null") {
      this.isOpen = false;
      if (actionUrl.startsWith("http")) {
        window.location.href = actionUrl;
      } else {
        // Internal navigation
        window.location.href = actionUrl;
      }
    }
  }

  async handleMarkAllRead(event) {
    event.stopPropagation();
    try {
      await markAllAsRead();
      await this.refreshData();
    } catch (error) {
      console.error("Failed to mark all as read:", error);
    }
  }

  async refreshData() {
    await Promise.all([
      refreshApex(this.wiredNotificationsResult),
      refreshApex(this.wiredCountResult)
    ]);
  }

  getTypeClass(type) {
    switch (type) {
      case "Success":
        return "type-success";
      case "Warning":
        return "type-warning";
      case "Alert":
        return "type-alert";
      default:
        return "type-info";
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
}
