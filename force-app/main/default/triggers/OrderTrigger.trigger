trigger OrderTrigger on Order(after update) {
  if (Trigger.isUpdate) {
    CkOrderNotificationHandler.notifyOnStatusChange(
      Trigger.new,
      Trigger.oldMap
    );
  }
}
