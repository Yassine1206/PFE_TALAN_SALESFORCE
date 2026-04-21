trigger CartItemTrigger on Cart_Item__c (after insert, after update, after delete) {

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CartItemTriggerHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            CartItemTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            CartItemTriggerHandler.handleAfterDelete(Trigger.old);
        }
    }
}