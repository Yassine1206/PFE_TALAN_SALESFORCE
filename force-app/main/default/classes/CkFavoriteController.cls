public without sharing class CkFavoriteController {
    
    @AuraEnabled
    public static Boolean toggleFavorite(String productId) {
        try {
            String userId = System.UserInfo.getUserId();
            String userType = System.UserInfo.getUserType();
            if (userType == 'Guest') {
                throw new AuraHandledException('Please sign in to add favorites.');
            }
            
            List<Favorite__c> existing = [
                SELECT Id FROM Favorite__c WHERE User__c = :userId AND Product2__c = :productId LIMIT 1
            ];
            
            if (!existing.isEmpty()) {
                delete existing;
                return false;
            } else {
                Favorite__c fav = new Favorite__c(User__c = userId, Product2__c = productId);
                insert fav;
                return true;
            }
        } catch (AuraHandledException e) { throw e;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean isFavorite(String productId) {
        try {
            String userId = System.UserInfo.getUserId();
            String userType = System.UserInfo.getUserType();
            if (userType == 'Guest') return false;
            return [SELECT COUNT() FROM Favorite__c WHERE User__c = :userId AND Product2__c = :productId LIMIT 1] > 0;
        } catch (Exception e) { return false; }
    }
    
    @AuraEnabled
    public static void trackProductView(String productId) {
        try {
            String userId = System.UserInfo.getUserId();
            String userType = System.UserInfo.getUserType();
            if (userType == 'Guest') return;
            
            List<Product_View__c> existing = [
                SELECT Id, View_Count__c FROM Product_View__c WHERE User__c = :userId AND Product2__c = :productId LIMIT 1
            ];
            
            if (!existing.isEmpty()) {
                existing[0].View_Count__c = existing[0].View_Count__c + 1;
                update existing;
            } else {
                insert new Product_View__c(User__c = userId, Product2__c = productId, View_Count__c = 1);
            }
        } catch (Exception e) { System.debug('Track view failed: ' + e.getMessage()); }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getUserFavoriteIds() {
        try {
            String userId = System.UserInfo.getUserId();
            String userType = System.UserInfo.getUserType();
            if (userType == 'Guest') return new List<String>();
            
            List<String> favIds = new List<String>();
            for (Favorite__c f : [SELECT Product2__c FROM Favorite__c WHERE User__c = :userId]) {
                favIds.add(f.Product2__c);
            }
            return favIds;
        } catch (Exception e) { return new List<String>(); }
    }
    
    @AuraEnabled
    public static List<FavoriteProduct> getUserFavorites() {
        try {
            String userId   = System.UserInfo.getUserId();
            String userType = System.UserInfo.getUserType();
            
            // FIX : même correctif que CkCartController
            // 'Standard' = Admin SF qui teste → doit voir ses favoris
            // Seul 'Guest' est vraiment non connecté
            if (userType == 'Guest') return new List<FavoriteProduct>();
            
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            List<Favorite__c> favorites = [
            SELECT Id, Product2__c, Product2__r.Name, Product2__r.Image_URL__c, 
                   Product2__r.Description, Product2__r.Product_Category__r.Name, 
                   Product2__r.Rating__c, CreatedDate
            FROM Favorite__c 
            WHERE User__c = :userId AND Product2__r.IsActive = true
            ORDER BY CreatedDate DESC
        ];
            
            Set<Id> productIds = new Set<Id>();
            for (Favorite__c f : favorites) productIds.add(f.Product2__c);
            
            Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
            for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice FROM PricebookEntry
            WHERE Product2Id IN :productIds 
            AND Pricebook2Id = :stdPB 
            AND IsActive = true
        ]) {
                priceMap.put(pbe.Product2Id, pbe.UnitPrice);
            }
            
            List<FavoriteProduct> result = new List<FavoriteProduct>();
            for (Favorite__c f : favorites) {
                Decimal price        = priceMap.containsKey(f.Product2__c)
                    ? priceMap.get(f.Product2__c) : 0;
                FavoriteProduct fp   = new FavoriteProduct();
                fp.favoriteId        = f.Id;
                fp.productId         = f.Product2__c;
                fp.name              = f.Product2__r.Name;
                fp.price             = '$' + price.setScale(2).toPlainString();
                fp.priceNum          = price;
                fp.image             = f.Product2__r.Image_URL__c;
                fp.description       = f.Product2__r.Description;
                fp.category          = f.Product2__r.Product_Category__r != null
                    ? f.Product2__r.Product_Category__r.Name : '';
                fp.rating            = f.Product2__r.Rating__c;
                fp.addedDate         = f.CreatedDate.format('MMM d, yyyy');
                result.add(fp);
            }
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class FavoriteProduct {
        @AuraEnabled public String favoriteId;
        @AuraEnabled public String productId;
        @AuraEnabled public String name;
        @AuraEnabled public String price;
        @AuraEnabled public Decimal priceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal rating;
        @AuraEnabled public String addedDate;
    }
}