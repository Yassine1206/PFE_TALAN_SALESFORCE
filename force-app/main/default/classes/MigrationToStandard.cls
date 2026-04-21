public without sharing class MigrationToStandard {
    
    public static void migrateAll() {
        migrateProducts();
        migrateOrders();
        migrateFavorites();
        migrateProductViews();
        migrateBundleItems();
        migrateCartItemRefs();
    }
    
    public static void migrateProducts() {
        // Get Standard Pricebook
        Pricebook2 stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        
        List<Store_Product__c> oldProducts = [
            SELECT Id, Name, Price__c, Image_URL__c, Description__c, Rating__c,
                   Is_Active__c, Embedding__c, Stock_Quantity__c, Low_Stock_Threshold__c,
                   Old_Price__c, Discount_Percent__c, Is_On_Sale__c, Availability__c,
                   Product_Category__c, Product_Subcategory__c
            FROM Store_Product__c
        ];
        
        // Create Product2 records
        Map<Id, Product2> oldToNewProduct = new Map<Id, Product2>();
        List<Product2> newProducts = new List<Product2>();
        
        for (Store_Product__c old : oldProducts) {
            Product2 p = new Product2();
            p.Name = old.Name;
            p.Description = old.Description__c;
            p.IsActive = old.Is_Active__c;
            p.Image_URL__c = old.Image_URL__c;
            p.Rating__c = old.Rating__c;
            p.Embedding__c = old.Embedding__c;
            p.Stock_Quantity__c = old.Stock_Quantity__c;
            p.Low_Stock_Threshold__c = old.Low_Stock_Threshold__c;
            p.Old_Price__c = old.Old_Price__c;
            p.Discount_Percent__c = old.Discount_Percent__c;
            p.Is_On_Sale__c = old.Is_On_Sale__c;
            p.Availability__c = old.Availability__c;
            p.Product_Category__c = old.Product_Category__c;
            p.Product_Subcategory__c = old.Product_Subcategory__c;
            newProducts.add(p);
            oldToNewProduct.put(old.Id, p);
        }
        
        insert newProducts;
        System.debug('Migrated ' + newProducts.size() + ' products');
        
        // Create PricebookEntries
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        Integer i = 0;
        for (Store_Product__c old : oldProducts) {
            PricebookEntry pbe = new PricebookEntry();
            pbe.Pricebook2Id = stdPB.Id;
            pbe.Product2Id = newProducts[i].Id;
            pbe.UnitPrice = old.Price__c;
            pbe.IsActive = true;
            pbes.add(pbe);
            i++;
        }
        
        insert pbes;
        System.debug('Created ' + pbes.size() + ' pricebook entries');
        
        // Save mapping for other migrations
        // Store old ID -> new ID in a temporary object or use static variable
        migrationMap = new Map<String, String>();
        i = 0;
        for (Store_Product__c old : oldProducts) {
            migrationMap.put(old.Id, newProducts[i].Id);
            i++;
        }
    }
    
    static Map<String, String> migrationMap = new Map<String, String>();
    
    public static void migrateOrders() {
        if (migrationMap.isEmpty()) {
            // Build map from existing data
            buildMigrationMap();
        }
        
        List<Store_Order__c> oldOrders = [
            SELECT Id, User__c, Status__c, Subtotal__c, Shipping_Cost__c, Discount__c, 
                   Total__c, Shipping_Method__c, Shipping_Address__c, Shipping_City__c,
                   Shipping_Country__c, Shipping_Zip__c, Phone__c, Email__c,
                   Promo_Code__c, Stripe_Payment_Id__c, CreatedDate
            FROM Store_Order__c
        ];
        
        if (oldOrders.isEmpty()) {
            System.debug('No orders to migrate');
            return;
        }
        
        // Get Account for orders (use first Account or create one)
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        Id accountId;
        if (accts.isEmpty()) {
            Account a = new Account(Name = 'TalFlow Customers');
            insert a;
            accountId = a.Id;
        } else {
            accountId = accts[0].Id;
        }
        
        // Get Standard Pricebook
        Pricebook2 stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        
        Map<Id, Order> oldToNewOrder = new Map<Id, Order>();
        List<Order> newOrders = new List<Order>();
        
        for (Store_Order__c old : oldOrders) {
            Order o = new Order();
            o.AccountId = accountId;
            o.EffectiveDate = old.CreatedDate.date();
            o.Status = 'Draft';
            o.Pricebook2Id = stdPB.Id;
            o.Subtotal__c = old.Subtotal__c;
            o.Shipping_Cost__c = old.Shipping_Cost__c;
            o.Discount__c = old.Discount__c;
            o.Order_Total__c = old.Total__c;
            o.Shipping_Method__c = old.Shipping_Method__c;
            o.Shipping_Address__c = old.Shipping_Address__c;
            o.Shipping_City__c = old.Shipping_City__c;
            o.Shipping_Country__c = old.Shipping_Country__c;
            o.Shipping_Zip__c = old.Shipping_Zip__c;
            o.Phone__c = old.Phone__c;
            o.Email__c = old.Email__c;
            o.Promo_Code__c = old.Promo_Code__c;
            o.Stripe_Payment_Id__c = old.Stripe_Payment_Id__c;
            newOrders.add(o);
            oldToNewOrder.put(old.Id, o);
        }
        
        insert newOrders;
        System.debug('Migrated ' + newOrders.size() + ' orders');
        
        // Migrate OrderItems
        List<Order_Item__c> oldItems = [
            SELECT Id, Store_Order__c, Product_Name__c, Product_Image__c, 
                   Product_Id__c, Unit_Price__c, Quantity__c
            FROM Order_Item__c
        ];
        
        // Build PricebookEntry map
        Map<Id, Id> product2ToPBE = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :stdPB.Id
        ]) {
            product2ToPBE.put(pbe.Product2Id, pbe.Id);
        }
        
        List<OrderItem> newItems = new List<OrderItem>();
        Integer idx = 0;
        for (Order_Item__c old : oldItems) {
            // Find the new order
            Order newOrder = oldToNewOrder.get(old.Store_Order__c);
            if (newOrder == null) continue;
            
            // Find the new product ID
            String newProductId = migrationMap.get(old.Product_Id__c);
            if (newProductId == null) continue;
            
            // Find PricebookEntry
            Id pbeId = product2ToPBE.get(Id.valueOf(newProductId));
            if (pbeId == null) continue;
            
            OrderItem oi = new OrderItem();
            oi.OrderId = newOrder.Id;
            oi.Product2Id = Id.valueOf(newProductId);
            oi.PricebookEntryId = pbeId;
            oi.Quantity = old.Quantity__c;
            oi.UnitPrice = old.Unit_Price__c;
            oi.Product_Image__c = old.Product_Image__c;
            oi.Product_Name_Text__c = old.Product_Name__c;
            newItems.add(oi);
        }
        
        insert newItems;
        System.debug('Migrated ' + newItems.size() + ' order items');
    }
    
    public static void migrateFavorites() {
        if (migrationMap.isEmpty()) buildMigrationMap();
        
        List<Favorite__c> favs = [SELECT Id, Product__c FROM Favorite__c WHERE Product__c != null];
        for (Favorite__c f : favs) {
            String newId = migrationMap.get(f.Product__c);
            if (newId != null) {
                f.Product2__c = Id.valueOf(newId);
            }
        }
        update favs;
        System.debug('Migrated ' + favs.size() + ' favorites');
    }
    
    public static void migrateProductViews() {
        if (migrationMap.isEmpty()) buildMigrationMap();
        
        List<Product_View__c> views = [SELECT Id, Product__c FROM Product_View__c WHERE Product__c != null];
        for (Product_View__c v : views) {
            String newId = migrationMap.get(v.Product__c);
            if (newId != null) {
                v.Product2__c = Id.valueOf(newId);
            }
        }
        update views;
        System.debug('Migrated ' + views.size() + ' product views');
    }
    
    public static void migrateBundleItems() {
        if (migrationMap.isEmpty()) buildMigrationMap();
        
        List<Bundle_Item__c> items = [SELECT Id, Product__c FROM Bundle_Item__c WHERE Product__c != null];
        for (Bundle_Item__c bi : items) {
            String newId = migrationMap.get(bi.Product__c);
            if (newId != null) {
                bi.Product2__c = Id.valueOf(newId);
            }
        }
        update items;
        System.debug('Migrated ' + items.size() + ' bundle items');
    }
    
    public static void migrateCartItemRefs() {
        if (migrationMap.isEmpty()) buildMigrationMap();
        
        List<Cart_Item__c> items = [SELECT Id, Product_Id_c__c FROM Cart_Item__c WHERE Product_Id_c__c != null];
        for (Cart_Item__c ci : items) {
            String newId = migrationMap.get(ci.Product_Id_c__c);
            if (newId != null) {
                ci.Product_Id_c__c = newId;
            }
        }
        update items;
        System.debug('Migrated ' + items.size() + ' cart item references');
    }
    
    private static void buildMigrationMap() {
        // Match by Name since we can't store the mapping permanently
        Map<String, Id> nameToProduct2 = new Map<String, Id>();
        for (Product2 p : [SELECT Id, Name FROM Product2]) {
            nameToProduct2.put(p.Name, p.Id);
        }
        
        migrationMap = new Map<String, String>();
        for (Store_Product__c sp : [SELECT Id, Name FROM Store_Product__c]) {
            Id newId = nameToProduct2.get(sp.Name);
            if (newId != null) {
                migrationMap.put(sp.Id, String.valueOf(newId));
            }
        }
        System.debug('Built migration map: ' + migrationMap.size() + ' mappings');
    }
}