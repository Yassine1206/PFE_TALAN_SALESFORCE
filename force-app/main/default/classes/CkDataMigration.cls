public without sharing class CkDataMigration {
    
    public static void migrateCategories() {
        // 1. Get all unique categories from products
        Map<String, Product_Category__c> catMap = new Map<String, Product_Category__c>();
        
        List<AggregateResult> cats = [
            SELECT Category__c cat
            FROM Store_Product__c
            WHERE Category__c != null AND Is_Active__c = true
            GROUP BY Category__c
            ORDER BY Category__c
        ];
        
        Integer sortOrder = 1;
        for (AggregateResult ar : cats) {
            String catName = (String) ar.get('cat');
            Product_Category__c pc = new Product_Category__c();
            pc.Name = catName;
            pc.Is_Active__c = true;
            pc.Sort_Order__c = sortOrder++;
            catMap.put(catName, pc);
        }
        
        insert catMap.values();
        System.debug('Created ' + catMap.size() + ' categories');
        
        // 2. Get all unique subcategories
        Map<String, Product_Subcategory__c> subMap = new Map<String, Product_Subcategory__c>();
        
        List<AggregateResult> subs = [
            SELECT Category__c cat, Subcategory__c sub
            FROM Store_Product__c
            WHERE Subcategory__c != null AND Is_Active__c = true
            GROUP BY Category__c, Subcategory__c
            ORDER BY Category__c, Subcategory__c
        ];
        
        Integer subSort = 1;
        for (AggregateResult ar : subs) {
            String catName = (String) ar.get('cat');
            String subName = (String) ar.get('sub');
            String key = catName + '::' + subName;
            
            if (catMap.containsKey(catName)) {
                Product_Subcategory__c ps = new Product_Subcategory__c();
                ps.Name = subName;
                ps.Product_Category__c = catMap.get(catName).Id;
                ps.Is_Active__c = true;
                ps.Sort_Order__c = subSort++;
                subMap.put(key, ps);
            }
        }
        
        if (!subMap.isEmpty()) {
            insert subMap.values();
        }
        System.debug('Created ' + subMap.size() + ' subcategories');
        
        // 3. Update all products with the new lookups
        List<Store_Product__c> products = [
            SELECT Id, Category__c, Subcategory__c
            FROM Store_Product__c
            WHERE Category__c != null
        ];
        
        List<Store_Product__c> toUpdate = new List<Store_Product__c>();
        for (Store_Product__c p : products) {
            Store_Product__c upd = new Store_Product__c(Id = p.Id);
            
            if (catMap.containsKey(p.Category__c)) {
                upd.Product_Category__c = catMap.get(p.Category__c).Id;
            }
            
            if (String.isNotBlank(p.Subcategory__c)) {
                String key = p.Category__c + '::' + p.Subcategory__c;
                if (subMap.containsKey(key)) {
                    upd.Product_Subcategory__c = subMap.get(key).Id;
                }
            }
            
            toUpdate.add(upd);
        }
        
        update toUpdate;
        System.debug('Updated ' + toUpdate.size() + ' products with new lookups');
    }
    
    // Set category images (run after migration, update URLs as needed)
    public static void setCategoryImages() {
        Map<String, String> imageMap = new Map<String, String>{
            'Audio' => 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600',
            'Phone Accessories' => 'https://images.unsplash.com/photo-1583394838336-acd977736f90?w=600',
            'Smartwatches' => 'https://images.unsplash.com/photo-1546868871-af0de0ae72be?w=600',
            'Computer Accessories' => 'https://images.unsplash.com/photo-1527814050087-3793815479db?w=600',
            'Smart Home' => 'https://images.unsplash.com/photo-1558089687-f282ffcbc126?w=600',
            'Gaming' => 'https://images.unsplash.com/photo-1612287230202-1ff1d85d1bdf?w=600',
            'Wearables' => 'https://images.unsplash.com/photo-1575311373937-040b8e1fd5b6?w=600',
            'Camera' => 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=600',
            'Cables' => 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=600',
            'Drones' => 'https://images.unsplash.com/photo-1473968512647-3e447244af8f?w=600'
        };
        
        List<Product_Category__c> cats = [SELECT Id, Name FROM Product_Category__c];
        for (Product_Category__c cat : cats) {
            if (imageMap.containsKey(cat.Name)) {
                cat.Image_URL__c = imageMap.get(cat.Name);
            }
        }
        update cats;
        System.debug('Updated ' + cats.size() + ' category images');
    }
}