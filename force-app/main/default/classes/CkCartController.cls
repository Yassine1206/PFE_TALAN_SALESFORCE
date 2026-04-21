public without sharing class CkCartController {
    
    @AuraEnabled
    public static CartData getCart() {
        try {
            String userType = System.UserInfo.getUserType();
            Boolean isGuest = userType == 'Guest';
            
            if (isGuest) {
                CartData data = new CartData();
                data.isGuest = true;
                data.items   = new List<CartItemData>();
                return data;
            }
            
            String userId = System.UserInfo.getUserId();
            
            List<Cart__c> carts = [
                SELECT Id, Total__c,
                    (SELECT Id, Product_Name_c__c, Product_Image_c__c,
                            Product_Id_c__c, Unit_Price_c__c,
                            Quantity_c__c, Line_Total_c__c
                     FROM Cart_Items__r
                     ORDER BY CreatedDate ASC)
                FROM Cart__c
                WHERE User__c = :userId
                AND Status__c = 'Active'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            CartData data = new CartData();
            data.isGuest  = false;
            
            if (carts.isEmpty()) {
                data.cartId = null;
                data.items  = new List<CartItemData>();
                data.total  = 0;
                return data;
            }
            
            Cart__c cart = carts[0];
            data.cartId  = cart.Id;
            data.items   = new List<CartItemData>();
            
            Decimal total = 0;
            for (Cart_Item__c item : cart.Cart_Items__r) {
                data.items.add(mapItem(item));
                // Line_Total_c__c est formula → calculé auto par Salesforce
                // On calcule manuellement pour le total du cart
                Decimal lineTotal = item.Unit_Price_c__c != null && item.Quantity_c__c != null
                    ? item.Unit_Price_c__c * item.Quantity_c__c : 0;
                total += lineTotal;
            }
            data.total = total;
            
            return data;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static CartItemData addToCart(
        String productId, String productName,
    String productImage, Decimal unitPrice
    ) {
        try {
            String userId = System.UserInfo.getUserId();
            if (unitPrice == null || unitPrice < 0) unitPrice = 0;
            
            Id cartId = getOrCreateCart(userId);
            
            List<Cart_Item__c> existingItems = [
                SELECT Id, Quantity_c__c, Unit_Price_c__c
                FROM Cart_Item__c
                WHERE Cart_c__c = :cartId
                AND Product_Id_c__c = :productId
                LIMIT 1
            ];
            
            Cart_Item__c cartItem;
            
            if (!existingItems.isEmpty()) {
                // Incrémenter la quantité
                cartItem               = existingItems[0];
                Decimal currentQty     = cartItem.Quantity_c__c != null
                    ? cartItem.Quantity_c__c : 0;
                cartItem.Quantity_c__c = currentQty + 1;
                // FIX : Line_Total_c__c est formula → NE PAS l'écrire
                update cartItem;
            } else {
                // Créer un nouvel item
                cartItem                    = new Cart_Item__c();
                cartItem.Cart_c__c          = cartId;
                cartItem.Product_Id_c__c    = productId;
                cartItem.Product_Name_c__c  = productName  != null ? productName  : '';
                cartItem.Product_Image_c__c = productImage != null ? productImage : '';
                cartItem.Unit_Price_c__c    = unitPrice;
                cartItem.Quantity_c__c      = 1;
                // FIX : Line_Total_c__c est formula → NE PAS l'écrire
                insert cartItem;
            }
            
            
            Cart_Item__c updated = [
                SELECT Id, Product_Name_c__c, Product_Image_c__c,
                       Product_Id_c__c, Unit_Price_c__c,
                       Quantity_c__c, Line_Total_c__c
                FROM Cart_Item__c
                WHERE Id = :cartItem.Id
                LIMIT 1
            ];
            
            return mapItem(updated);
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void updateQuantity(String itemId, Integer quantity) {
        try {
            if (quantity == null || quantity < 1) quantity = 1;
            
            Cart_Item__c item = [
                SELECT Id, Cart_c__c, Unit_Price_c__c
                FROM Cart_Item__c
                WHERE Id = :itemId
                LIMIT 1
            ];
            
            // FIX : seulement Quantity — Line_Total est formula
            item.Quantity_c__c = quantity;
            update item;
            
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void removeItem(String itemId) {
        try {
            Cart_Item__c item = [
                SELECT Id, Cart_c__c
                FROM Cart_Item__c
                WHERE Id = :itemId
                LIMIT 1
            ];
            
            Id cartId = item.Cart_c__c;
            delete item;
            
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── HELPERS ───────────────────────────────────────────────
    
    private static Id getOrCreateCart(String userId) {
        List<Cart__c> carts = [
            SELECT Id FROM Cart__c
            WHERE User__c = :userId AND Status__c = 'Active'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!carts.isEmpty()) return carts[0].Id;
        
        Cart__c newCart   = new Cart__c();
        newCart.User__c   = userId;
        newCart.Status__c = 'Active';
        newCart.Total__c  = 0;
        insert newCart;
        return newCart.Id;
    }
    
   
    
    private static CartItemData mapItem(Cart_Item__c item) {
        CartItemData cid = new CartItemData();
        cid.itemId    = item.Id;
        cid.productId = item.Product_Id_c__c;
        cid.name      = item.Product_Name_c__c  != null ? item.Product_Name_c__c  : '';
        cid.image     = item.Product_Image_c__c != null ? item.Product_Image_c__c : '';
        cid.unitPrice = item.Unit_Price_c__c    != null ? item.Unit_Price_c__c    : 0;
        cid.quantity  = item.Quantity_c__c      != null
            ? Integer.valueOf(item.Quantity_c__c) : 1;
        // Line_Total formula → si null on calcule
        cid.lineTotal = item.Line_Total_c__c    != null
            ? item.Line_Total_c__c
            : (cid.unitPrice * cid.quantity);
        return cid;
    }
    
    public class CartData {
        @AuraEnabled public Boolean            isGuest = false;
        @AuraEnabled public String             cartId;
        @AuraEnabled public List<CartItemData> items;
        @AuraEnabled public Decimal            total;
    }
    
    public class CartItemData {
        @AuraEnabled public String  itemId;
        @AuraEnabled public String  productId;
        @AuraEnabled public String  name;
        @AuraEnabled public String  image;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal lineTotal;
    }
}