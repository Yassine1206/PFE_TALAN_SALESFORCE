public with sharing class CkNotificationController {
  @AuraEnabled(cacheable=true)
  public static List<Notification__c> getMyNotifications(Integer maxResults) {
    if (maxResults == null || maxResults <= 0)
      maxResults = 10;

    Id userId = UserInfo.getUserId();

    return [
      SELECT
        Id,
        Name,
        Title__c,
        Message__c,
        Type__c,
        Is_Read__c,
        Action_URL__c,
        Icon__c,
        CreatedDate
      FROM Notification__c
      WHERE User_Id__c = :userId
      ORDER BY CreatedDate DESC
      LIMIT :maxResults
    ];
  }

  /**
   * @description Returns the count of unread notifications.
   */
  @AuraEnabled(cacheable=true)
  public static Integer getUnreadCount() {
    Id userId = UserInfo.getUserId();

    return [
      SELECT COUNT()
      FROM Notification__c
      WHERE User_Id__c = :userId AND Is_Read__c = FALSE
    ];
  }

  /**
   * @description Marks a single notification as read.
   */
  @AuraEnabled
  public static void markAsRead(Id notificationId) {
    if (notificationId == null)
      return;

    Notification__c notif = [
      SELECT Id, Is_Read__c
      FROM Notification__c
      WHERE Id = :notificationId AND User_Id__c = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!notif.Is_Read__c) {
      notif.Is_Read__c = true;
      update notif;
    }
  }

  /**
   * @description Marks all unread notifications of the current user as read.
   */
  @AuraEnabled
  public static void markAllAsRead() {
    Id userId = UserInfo.getUserId();

    List<Notification__c> unread = [
      SELECT Id, Is_Read__c
      FROM Notification__c
      WHERE User_Id__c = :userId AND Is_Read__c = FALSE
    ];

    for (Notification__c n : unread) {
      n.Is_Read__c = true;
    }

    if (!unread.isEmpty()) {
      update unread;
    }
  }

  /**
   * @description Creates a notification programmatically.
   * Used by triggers and services to push notifications to users.
   */
  public static void createNotification(
    Id userId,
    String title,
    String message,
    String type,
    String actionUrl,
    String icon
  ) {
    if (userId == null || String.isBlank(title) || String.isBlank(message))
      return;

    Notification__c notif = new Notification__c();
    notif.User_Id__c = userId;
    notif.Title__c = title.left(100);
    notif.Message__c = message.left(500);
    notif.Type__c = String.isNotBlank(type) ? type : 'Info';
    notif.Action_URL__c = actionUrl;
    notif.Icon__c = icon;
    notif.Is_Read__c = false;

    try {
      insert notif;
    } catch (Exception e) {
      System.debug('Failed to create notification: ' + e.getMessage());
    }
  }
}
