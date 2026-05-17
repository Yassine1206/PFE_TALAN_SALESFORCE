/**
 * @description Centralized service to send native Salesforce notifications
 *              to internal users (Admin, Sales Manager, Commercial Agent).
 *              Uses Custom Notification API.
 */
public without sharing class CkInternalNotificationService {
  // Notification Type Developer Names
  public static final String TYPE_NEW_LEAD = 'B2B_New_Lead';
  public static final String TYPE_QUOTE_ACTIVITY = 'B2B_Quote_Activity';
  public static final String TYPE_URGENT_QUOTE = 'B2B_Urgent_Quote';
  public static final String TYPE_ORDER_ACTIVITY = 'B2B_Order_Activity';
  public static final String TYPE_CONTRACT_SIGNED = 'B2B_Contract_Signed';
  public static final String TYPE_STOCK_LOW = 'B2B_Stock_Low';
  public static final String TYPE_LIVE_CHAT = 'B2B_Live_Chat_Request';

  // Role names
  public static final String ROLE_SALES_MANAGER = 'Sales_Manager';
  public static final String ROLE_COMMERCIAL_AGENT = 'Commercial_Agent';

  /**
   * @description Send a custom notification to specific users.
   * @param notificationTypeDevName Developer Name of the Custom Notification Type
   * @param title Notification title (max 80 chars)
   * @param body Notification body (max 750 chars)
   * @param recipientUserIds Set of user IDs to notify
   * @param targetRecordId Record to open when notification is clicked (optional)
   */
  public static void send(
    String notificationTypeDevName,
    String title,
    String body,
    Set<Id> recipientUserIds,
    Id targetRecordId
  ) {
    if (recipientUserIds == null || recipientUserIds.isEmpty()) {
      System.debug('No recipients for notification');
      return;
    }

    try {
      // Get Custom Notification Type Id
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :notificationTypeDevName
        LIMIT 1
      ];

      if (types.isEmpty()) {
        System.debug(
          '❌ Notification type not found: ' + notificationTypeDevName
        );
        return;
      }

      // Build notification
      Messaging.CustomNotification notif = new Messaging.CustomNotification();
      notif.setNotificationTypeId(types[0].Id);
      notif.setTitle(
        title.length() > 80 ? title.substring(0, 77) + '...' : title
      );
      notif.setBody(
        body.length() > 750 ? body.substring(0, 747) + '...' : body
      );

      // Salesforce REQUIRES a target. Use fallback if none provided.
      if (targetRecordId != null) {
        notif.setTargetId(targetRecordId);
      } else {
        // Fallback : use the first recipient's user ID as target
        List<Id> idList = new List<Id>(recipientUserIds);
        notif.setTargetId(idList[0]);
      }

      // ⭐ FIX: Convert Set<Id> to Set<String>
      Set<String> recipientStrings = new Set<String>();
      for (Id userId : recipientUserIds) {
        recipientStrings.add(String.valueOf(userId));
      }

      // Send
      notif.send(recipientStrings);
      System.debug(
        '✅ Sent notification "' +
          title +
          '" to ' +
          recipientStrings.size() +
          ' users'
      );
    } catch (Exception e) {
      System.debug('❌ Failed to send notification: ' + e.getMessage());
    }
  }

  /**
   * @description Get all user IDs that have a specific role.
   * @param roleDevName Developer name of the role
   */
  public static Set<Id> getUsersByRole(String roleDevName) {
    Set<Id> userIds = new Set<Id>();

    for (User u : [
      SELECT Id
      FROM User
      WHERE UserRole.DeveloperName = :roleDevName AND IsActive = TRUE
    ]) {
      userIds.add(u.Id);
    }

    return userIds;
  }

  /**
   * @description Get all admin user IDs (System Administrator profile).
   */
  public static Set<Id> getAdminUserIds() {
    Set<Id> userIds = new Set<Id>();

    for (User u : [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
    ]) {
      userIds.add(u.Id);
    }

    return userIds;
  }

  /**
   * @description Helper: get Sales Manager + Commercial Agent user IDs.
   */
  public static Set<Id> getSalesTeamUserIds() {
    Set<Id> userIds = getUsersByRole(ROLE_SALES_MANAGER);
    userIds.addAll(getUsersByRole(ROLE_COMMERCIAL_AGENT));
    return userIds;
  }
}
