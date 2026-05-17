trigger QuoteTrigger on Quote(after insert, after update) {
  if (Trigger.isAfter && Trigger.isInsert) {
    CkQuoteTriggerHandler.notifyInternalOnNewQuote(Trigger.new); // ⭐ NEW
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    CkQuoteTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    CkQuoteTriggerHandler.notifyOnStatusChange(Trigger.new, Trigger.oldMap);
    CkQuoteTriggerHandler.notifyInternalTeam(Trigger.new, Trigger.oldMap);
    CkQuoteTriggerHandler.createOrderFromAcceptedQuote(
      Trigger.new,
      Trigger.oldMap
    );
  }
}
