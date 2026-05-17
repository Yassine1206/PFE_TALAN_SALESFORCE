trigger ReviewTrigger on Review__c(after insert, after update, after delete) {
  if (Trigger.isAfter && Trigger.isInsert) {
    CkReviewTriggerHandler.handleAfterInsert(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    CkReviewTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    CkReviewTriggerHandler.handleAfterDelete(Trigger.old);
  }
}
