trigger Product2Trigger on Product2 (before insert, before update) {

    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            Product2TriggerHandler.handleBeforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            Product2TriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}