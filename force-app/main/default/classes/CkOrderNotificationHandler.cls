/**
 * @description Trigger handler for Order notifications.
 */
public without sharing class CkOrderNotificationHandler {
  public static void notifyOnStatusChange(
    List<Order> newOrders,
    Map<Id, Order> oldMap
  ) {
    if (oldMap == null)
      return;

    Set<Id> accountIds = new Set<Id>();
    Map<Id, Order> toNotify = new Map<Id, Order>();

    for (Order o : newOrders) {
      Order oldOrder = oldMap.get(o.Id);

      // Trigger only on Status change
      if (o.Status == oldOrder.Status)
        continue;

      // Notify on Shipped, Delivered, Activated
      if (
        o.Status == 'Shipped' ||
        o.Status == 'Delivered' ||
        o.Status == 'Activated'
      ) {
        if (o.AccountId != null) {
          accountIds.add(o.AccountId);
          toNotify.put(o.Id, o);
        }
      }
    }

    if (toNotify.isEmpty())
      return;

    Map<Id, User> userByAccount = new Map<Id, User>();
    for (User u : [
      SELECT Id, AccountId
      FROM User
      WHERE AccountId IN :accountIds AND IsActive = TRUE
    ]) {
      userByAccount.put(u.AccountId, u);
    }

    List<Notification__c> toInsert = new List<Notification__c>();

    for (Order o : toNotify.values()) {
      User u = userByAccount.get(o.AccountId);
      if (u == null)
        continue;

      String title;
      String message;
      String type;
      String emoji;

      if (o.Status == 'Shipped') {
        title = 'Order Shipped';
        emoji = '📦';
        type = 'Success';
        message =
          emoji +
          ' Your order ' +
          o.OrderNumber +
          ' has been shipped! ' +
          'You will receive a tracking number shortly.';
      } else if (o.Status == 'Delivered') {
        title = 'Order Delivered';
        emoji = '✅';
        type = 'Success';
        message =
          emoji +
          ' Your order ' +
          o.OrderNumber +
          ' has been delivered. ' +
          'Thank you for choosing TalFlow!';
      } else {
        // Activated
        title = 'Order Confirmed';
        emoji = '🎉';
        type = 'Info';
        Decimal amt = o.TotalAmount != null ? o.TotalAmount : 0;
        message =
          emoji +
          ' Your order ' +
          o.OrderNumber +
          ' ($' +
          amt.setScale(0).format() +
          ') has been confirmed.';
      }

      Notification__c n = new Notification__c();
      n.User_Id__c = u.Id;
      n.Title__c = title;
      n.Message__c = message;
      n.Type__c = type;
      n.Action_URL__c = '/TalFlowExpress/s/my-orders';
      n.Is_Read__c = false;

      toInsert.add(n);
    }

    if (!toInsert.isEmpty()) {
      try {
        insert toInsert;
        System.debug('✅ Created ' + toInsert.size() + ' order notifications');
      } catch (Exception e) {
        System.debug('❌ Failed: ' + e.getMessage());
      }
    }
  }
}
