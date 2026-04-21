public class CartItemTriggerHandler {
    
    public static void handleAfterInsert(List<Cart_Item__c> newItems) {
        recalculateCartTotals(newItems, null);
    }
    
    public static void handleAfterUpdate(List<Cart_Item__c> newItems, Map<Id, Cart_Item__c> oldMap) {
        recalculateCartTotals(newItems, oldMap);
    }
    
    public static void handleAfterDelete(List<Cart_Item__c> oldItems) {
        recalculateCartTotals(oldItems, null);
    }
    
    private static void recalculateCartTotals(
        List<Cart_Item__c> items,
    Map<Id, Cart_Item__c> oldMap
    ) {
        // 1. Collecter tous les Cart IDs concernés
        Set<Id> cartIds = new Set<Id>();
        for (Cart_Item__c item : items) {
            if (item.Cart_c__c != null) cartIds.add(item.Cart_c__c);
            if (oldMap != null && oldMap.containsKey(item.Id)) {
                Id oldCartId = oldMap.get(item.Id).Cart_c__c;
                if (oldCartId != null) cartIds.add(oldCartId);
            }
        }
        
        if (cartIds.isEmpty()) return;
        
        // 2. FIX : utiliser Unit_Price_c__c * Quantity_c__c directement
        // Line_Total_c__c est une formule → peut être null pour anciens items
        // → SUM(Line_Total_c__c) retourne null → "Argument cannot be null"
        Map<Id, Decimal> cartTotals = new Map<Id, Decimal>();
        for (Id cartId : cartIds) {
            cartTotals.put(cartId, 0);
        }
        
        for (Cart_Item__c ci : [
            SELECT Cart_c__c, Unit_Price_c__c, Quantity_c__c
            FROM Cart_Item__c
            WHERE Cart_c__c IN :cartIds
        ]) {
            Decimal price = ci.Unit_Price_c__c != null ? ci.Unit_Price_c__c : 0;
            Decimal qty   = ci.Quantity_c__c   != null ? ci.Quantity_c__c   : 0;
            Decimal current = cartTotals.get(ci.Cart_c__c);
            cartTotals.put(ci.Cart_c__c, current + (price * qty));
        }
        
        // 3. Mettre à jour les Carts
        List<Cart__c> cartsToUpdate = new List<Cart__c>();
        for (Id cartId : cartIds) {
            cartsToUpdate.add(new Cart__c(
                Id       = cartId,
            Total__c = cartTotals.get(cartId)
                ));
        }
        
        if (!cartsToUpdate.isEmpty()) update cartsToUpdate;
    }
}