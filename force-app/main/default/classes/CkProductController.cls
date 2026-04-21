public without sharing class CkProductController {
    
    @AuraEnabled(cacheable=true)
    public static List<ProductData> getProducts(Integer maxProducts, String category) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            String query = 'SELECT Id, Name, Description, Image_URL__c, ' +
                'Product_Category__r.Name, Rating__c, ' +
                '(SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1) ' +
                'FROM Product2 WHERE IsActive = true';
            
            if (String.isNotBlank(category) && category != 'All') {
                List<Product_Category__c> cats = [
                    SELECT Id FROM Product_Category__c WHERE Name = :category LIMIT 1
                ];
                if (!cats.isEmpty()) {
                    Id catId = cats[0].Id;
                    query += ' AND Product_Category__c = :catId';
                }
            }
            
            query += ' ORDER BY Rating__c DESC LIMIT :maxProducts';
            
            List<Product2> products = Database.query(query);
            List<ProductData> result = new List<ProductData>();
            
            for (Product2 p : products) {
                ProductData pd = buildProductData(p);
                result.add(pd);
            }
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getCategories() {
        try {
            List<String> categories = new List<String>();
            categories.add('All');
            
            for (Product_Category__c c : [
                SELECT Name FROM Product_Category__c 
                WHERE Is_Active__c = true 
                ORDER BY Sort_Order__c ASC, Name ASC
            ]) {
                categories.add(c.Name);
            }
            
            return categories;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static ProductData getProductById(String productId) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            Product2 p = [
                SELECT Id, Name, Description, Image_URL__c, 
                       Product_Category__r.Name, Rating__c,
                       (SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1)
                FROM Product2 
                WHERE Id = :productId AND IsActive = true
                LIMIT 1
            ];
            
            return buildProductData(p);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<ProductData> getRelatedProducts(String productId, String category, Integer maxResults) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            Product2 currentProduct = [
                SELECT Id, Embedding__c, Product_Category__c, Product_Category__r.Name
                FROM Product2 WHERE Id = :productId LIMIT 1
            ];
            
            List<Product2> candidates = [
                SELECT Id, Name, Description, Image_URL__c, 
                       Product_Category__r.Name, Rating__c, Embedding__c,
                       (SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1)
                FROM Product2 
                WHERE Id != :productId AND IsActive = true
            ];
            
            Set<String> boughtTogetherIds = new Set<String>();
            List<Id> cartIds = new List<Id>();
            for (Cart_Item__c ci : [SELECT Cart_c__c FROM Cart_Item__c WHERE Product_Id_c__c = :productId]) {
                cartIds.add(ci.Cart_c__c);
            }
            if (!cartIds.isEmpty()) {
                for (Cart_Item__c ci : [SELECT Product_Id_c__c FROM Cart_Item__c WHERE Cart_c__c IN :cartIds AND Product_Id_c__c != :productId]) {
                    boughtTogetherIds.add(ci.Product_Id_c__c);
                }
            }
            
            Set<String> userFavoriteIds = new Set<String>();
            String userType = System.UserInfo.getUserType();
            if (userType != 'Guest' && userType != 'Standard' && userType != 'Admin') {
                String userId = System.UserInfo.getUserId();
                for (Favorite__c f : [SELECT Product2__c FROM Favorite__c WHERE User__c = :userId]) {
                    userFavoriteIds.add(f.Product2__c);
                }
            }
            
            Map<Id, Decimal> viewCounts = new Map<Id, Decimal>();
            for (AggregateResult ar : [
                SELECT Product2__c prod, SUM(View_Count__c) totalViews 
                FROM Product_View__c GROUP BY Product2__c
            ]) {
                viewCounts.put((Id) ar.get('prod'), (Decimal) ar.get('totalViews'));
            }
            
            Decimal maxViews = 1;
            for (Decimal v : viewCounts.values()) {
                if (v > maxViews) maxViews = v;
            }
            
            List<Decimal> currentVector = null;
            if (String.isNotBlank(currentProduct.Embedding__c)) {
                currentVector = parseEmbedding(currentProduct.Embedding__c);
            }
            
            List<ScoredProduct> scored = new List<ScoredProduct>();
            
            for (Product2 candidate : candidates) {
                Decimal score = 0;
                
                if (currentVector != null && String.isNotBlank(candidate.Embedding__c)) {
                    List<Decimal> candidateVector = parseEmbedding(candidate.Embedding__c);
                    Decimal similarity = cosineSimilarity(currentVector, candidateVector);
                    score += similarity * 40;
                }
                
                if (boughtTogetherIds.contains(candidate.Id)) score += 30;
                if (userFavoriteIds.contains(candidate.Id)) score += 20;
                
                Decimal views = viewCounts.containsKey(candidate.Id) ? viewCounts.get(candidate.Id) : 0;
                score += (views / maxViews) * 10;
                
                ScoredProduct sp = new ScoredProduct();
                sp.product = candidate;
                sp.score = score;
                scored.add(sp);
            }
            
            scored.sort();
            
            List<ProductData> result = new List<ProductData>();
            Integer count = 0;
            for (ScoredProduct sp : scored) {
                if (count >= maxResults) break;
                result.add(buildProductData(sp.product));
                count++;
            }
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<ProductData> searchProducts(String searchTerm) {
        try {
            if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
                return new List<ProductData>();
            }
            
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            String searchQuery = '*' + String.escapeSingleQuotes(searchTerm) + '*';
            
            List<List<SObject>> searchResults = [
                FIND :searchQuery IN ALL FIELDS
                RETURNING Product2(
                Id, Name, Description, Image_URL__c, Product_Category__r.Name, Rating__c
                WHERE IsActive = true
                ORDER BY Rating__c DESC
                LIMIT 6
                )
                ];
            
            // Get prices separately
            Set<Id> productIds = new Set<Id>();
            for (Product2 p : (List<Product2>) searchResults[0]) {
                productIds.add(p.Id);
            }
            
            Map<Id, Decimal> priceMap = getPriceMap(productIds, stdPB);
            
            List<ProductData> result = new List<ProductData>();
            for (Product2 p : (List<Product2>) searchResults[0]) {
                ProductData pd = new ProductData();
                pd.id = p.Id;
                pd.name = p.Name;
                pd.image = p.Image_URL__c;
                pd.description = p.Description;
                pd.category = p.Product_Category__r != null ? p.Product_Category__r.Name : '';
                pd.rating = p.Rating__c;
                Decimal price = priceMap.containsKey(p.Id) ? priceMap.get(p.Id) : 0;
                pd.price = '$' + price.setScale(2).toPlainString();
                pd.priceNum = price;
                result.add(pd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static SearchResult searchProductsFull(String searchTerm, String category, String sortBy, Decimal minPrice, Decimal maxPrice, Integer pageNumber, Integer pageSize) {
        try {
            SearchResult sr = new SearchResult();
            sr.products = new List<ProductData>();
            sr.totalCount = 0;
            
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            String query = 'SELECT Id, Name, Description, Image_URL__c, Product_Category__r.Name, Rating__c, ' +
                '(SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1) ' +
                'FROM Product2 WHERE IsActive = true';
            String countQuery = 'SELECT COUNT() FROM Product2 WHERE IsActive = true';
            
            Set<Id> matchingIds = new Set<Id>();
            Boolean hasSearchTerm = String.isNotBlank(searchTerm) && searchTerm.length() >= 2;
            
            if (hasSearchTerm) {
                String searchQuery = '*' + String.escapeSingleQuotes(searchTerm) + '*';
                List<List<SObject>> soslResults = [
                    FIND :searchQuery IN ALL FIELDS
                    RETURNING Product2(Id WHERE IsActive = true)
                    ];
                for (Product2 p : (List<Product2>) soslResults[0]) {
                    matchingIds.add(p.Id);
                }
                if (matchingIds.isEmpty()) return sr;
                query += ' AND Id IN :matchingIds';
                countQuery += ' AND Id IN :matchingIds';
            }
            
            if (String.isNotBlank(category) && category != 'All') {
                List<Product_Category__c> cats = [SELECT Id FROM Product_Category__c WHERE Name = :category LIMIT 1];
                if (!cats.isEmpty()) {
                    Id catId = cats[0].Id;
                    query += ' AND Product_Category__c = :catId';
                    countQuery += ' AND Product_Category__c = :catId';
                }
            }
            
            if (sortBy == 'price_asc') query += ' ORDER BY Name ASC';
            else if (sortBy == 'price_desc') query += ' ORDER BY Name DESC';
            else if (sortBy == 'name_asc') query += ' ORDER BY Name ASC';
            else query += ' ORDER BY Rating__c DESC';
            
            Integer offset = (pageNumber - 1) * pageSize;
            query += ' LIMIT :pageSize OFFSET :offset';
            
            sr.totalCount = Database.countQuery(countQuery);
            
            List<Product2> products = Database.query(query);
            for (Product2 p : products) {
                ProductData pd = buildProductData(p);
                if (minPrice != null && pd.priceNum < minPrice) continue;
                if (maxPrice != null && pd.priceNum > maxPrice) continue;
                sr.products.add(pd);
            }
            
            return sr;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BestSellerData> getBestSellers(Integer maxProducts) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            List<AggregateResult> topSold = [
                SELECT Product2Id prodId, SUM(Quantity) totalQty
                FROM OrderItem
                WHERE Order.Status = 'Paid'
                GROUP BY Product2Id
                ORDER BY SUM(Quantity) DESC
                LIMIT :maxProducts
            ];
            
            Set<Id> productIds = new Set<Id>();
            Map<Id, Decimal> salesMap = new Map<Id, Decimal>();
            for (AggregateResult ar : topSold) {
                Id pid = (Id) ar.get('prodId');
                productIds.add(pid);
                salesMap.put(pid, (Decimal) ar.get('totalQty'));
            }
            
            if (productIds.isEmpty()) return new List<BestSellerData>();
            
            Map<Id, Product2> productMap = new Map<Id, Product2>([
                SELECT Id, Name, Image_URL__c, Product_Category__r.Name, Rating__c,
                    (SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1)
                FROM Product2 WHERE Id IN :productIds AND IsActive = true
            ]);
            
            List<BestSellerData> result = new List<BestSellerData>();
            for (AggregateResult ar : topSold) {
                Id pid = (Id) ar.get('prodId');
                Product2 p = productMap.get(pid);
                if (p == null) continue;
                
                BestSellerData bd = new BestSellerData();
                bd.id = p.Id;
                bd.name = p.Name;
                bd.image = p.Image_URL__c;
                bd.category = p.Product_Category__r != null ? p.Product_Category__r.Name : '';
                bd.rating = p.Rating__c;
                bd.totalSold = salesMap.get(pid).intValue();
                bd.rank = result.size() + 1;
                Decimal price = !p.PricebookEntries.isEmpty() ? p.PricebookEntries[0].UnitPrice : 0;
                bd.price = '$' + price.setScale(2).toPlainString();
                bd.priceNum = price;
                result.add(bd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<PromoProductData> getPromoProducts(Integer maxProducts) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            List<Product2> products = [
                SELECT Id, Name, Old_Price__c, Discount_Percent__c, 
                       Image_URL__c, Product_Category__r.Name, Rating__c,
                       (SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1)
                FROM Product2
                WHERE IsActive = true AND Is_On_Sale__c = true
                ORDER BY Discount_Percent__c DESC
                LIMIT :maxProducts
            ];
            
            List<PromoProductData> result = new List<PromoProductData>();
            for (Product2 p : products) {
                Decimal price = !p.PricebookEntries.isEmpty() ? p.PricebookEntries[0].UnitPrice : 0;
                PromoProductData pd = new PromoProductData();
                pd.id = p.Id;
                pd.name = p.Name;
                pd.newPrice = '$' + price.setScale(2).toPlainString();
                pd.oldPrice = p.Old_Price__c != null ? '$' + p.Old_Price__c.setScale(2).toPlainString() : '';
                pd.discountPercent = p.Discount_Percent__c != null ? p.Discount_Percent__c.intValue() : 0;
                pd.priceNum = price;
                pd.image = p.Image_URL__c;
                pd.category = p.Product_Category__r != null ? p.Product_Category__r.Name : '';
                pd.rating = p.Rating__c;
                result.add(pd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BundleData> getBundles(Integer maxBundles) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            
            List<Product_Bundle__c> bundles = [
                SELECT Id, Name, Description__c, Bundle_Price__c, Image_URL__c,
                    (SELECT Id, Product2__c, Product2__r.Name, Product2__r.Image_URL__c, 
                            Product2__r.Product_Category__r.Name, Sort_Order__c
                     FROM Bundle_Items__r ORDER BY Sort_Order__c ASC)
                FROM Product_Bundle__c
                WHERE Is_Active__c = true
                LIMIT :maxBundles
            ];
            
            // Get all product IDs from bundles
            Set<Id> allProductIds = new Set<Id>();
            for (Product_Bundle__c b : bundles) {
                for (Bundle_Item__c bi : b.Bundle_Items__r) {
                    if (bi.Product2__c != null) allProductIds.add(bi.Product2__c);
                }
            }
            
            Map<Id, Decimal> priceMap = getPriceMap(allProductIds, stdPB);
            
            List<BundleData> result = new List<BundleData>();
            for (Product_Bundle__c b : bundles) {
                BundleData bd = new BundleData();
                bd.id = b.Id;
                bd.name = b.Name;
                bd.description = b.Description__c;
                bd.bundlePrice = '$' + b.Bundle_Price__c.setScale(2).toPlainString();
                bd.bundlePriceNum = b.Bundle_Price__c;
                bd.image = b.Image_URL__c;
                
                Decimal totalIndividual = 0;
                bd.items = new List<BundleItemData>();
                for (Bundle_Item__c bi : b.Bundle_Items__r) {
                    if (bi.Product2__c == null) continue;
                    Decimal itemPrice = priceMap.containsKey(bi.Product2__c) ? priceMap.get(bi.Product2__c) : 0;
                    BundleItemData bid = new BundleItemData();
                    bid.id = bi.Id;
                    bid.productId = bi.Product2__c;
                    bid.name = bi.Product2__r.Name;
                    bid.price = '$' + itemPrice.setScale(2).toPlainString();
                    bid.priceNum = itemPrice;
                    bid.image = bi.Product2__r.Image_URL__c;
                    bid.category = bi.Product2__r.Product_Category__r != null ? bi.Product2__r.Product_Category__r.Name : '';
                    bd.items.add(bid);
                    totalIndividual += itemPrice;
                }
                
                bd.originalPrice = '$' + totalIndividual.setScale(2).toPlainString();
                bd.savings = '$' + (totalIndividual - b.Bundle_Price__c).setScale(2).toPlainString();
                result.add(bd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CategoryData> getCategoriesWithSubs() {
        try {
            List<Product_Category__c> cats = [
                SELECT Id, Name,
                    (SELECT Id, Name, Sort_Order__c FROM Products_Subcategories__r
                     WHERE Is_Active__c = true ORDER BY Sort_Order__c ASC, Name ASC)
                FROM Product_Category__c
                WHERE Is_Active__c = true
                ORDER BY Sort_Order__c ASC, Name ASC
            ];
            
            Map<Id, Integer> catCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Product_Category__c catId, COUNT(Id) cnt
                FROM Product2 WHERE IsActive = true AND Product_Category__c != null
                GROUP BY Product_Category__c
            ]) {
                catCounts.put((Id) ar.get('catId'), (Integer) ar.get('cnt'));
            }
            
            Map<Id, Integer> subCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Product_Subcategory__c subId, COUNT(Id) cnt
                FROM Product2 WHERE IsActive = true AND Product_Subcategory__c != null
                GROUP BY Product_Subcategory__c
            ]) {
                subCounts.put((Id) ar.get('subId'), (Integer) ar.get('cnt'));
            }
            
            List<CategoryData> result = new List<CategoryData>();
            for (Product_Category__c c : cats) {
                CategoryData cd = new CategoryData();
                cd.name = c.Name;
                cd.totalCount = catCounts.containsKey(c.Id) ? catCounts.get(c.Id) : 0;
                cd.subcategories = new List<SubcategoryData>();
                for (Product_Subcategory__c sub : c.Products_Subcategories__r) {
                    SubcategoryData sd = new SubcategoryData();
                    sd.name = sub.Name;
                    sd.count = subCounts.containsKey(sub.Id) ? subCounts.get(sub.Id) : 0;
                    cd.subcategories.add(sd);
                }
                result.add(cd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CategoryCardData> getCategoryCards() {
        try {
            List<Product_Category__c> cats = [
                SELECT Id, Name, Image_URL__c
                FROM Product_Category__c WHERE Is_Active__c = true
                ORDER BY Sort_Order__c ASC, Name ASC
            ];
            
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Product_Category__c catId, COUNT(Id) cnt
                FROM Product2 WHERE IsActive = true AND Product_Category__c != null
                GROUP BY Product_Category__c
            ]) {
                countMap.put((Id) ar.get('catId'), (Integer) ar.get('cnt'));
            }
            
            List<CategoryCardData> result = new List<CategoryCardData>();
            for (Product_Category__c c : cats) {
                CategoryCardData cd = new CategoryCardData();
                cd.name = c.Name;
                cd.image = c.Image_URL__c;
                cd.productCount = countMap.containsKey(c.Id) ? countMap.get(c.Id) : 0;
                cd.url = '/s/category?cat=' + EncodingUtil.urlEncode(c.Name, 'UTF-8');
                result.add(cd);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static CategoryPageResult getCategoryProducts(
        String category, String subcategory, String sortBy,
    Decimal minPrice, Decimal maxPrice,
    Boolean onSaleOnly, String availability,
    Integer pageNumber, Integer pageSize
    ) {
        try {
            Id stdPB = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            CategoryPageResult result = new CategoryPageResult();
            result.products = new List<CategoryProductData>();
            
            Id categoryId = null;
            if (String.isNotBlank(category)) {
                List<Product_Category__c> cats = [SELECT Id FROM Product_Category__c WHERE Name = :category LIMIT 1];
                if (!cats.isEmpty()) categoryId = cats[0].Id;
            }
            
            Id subcategoryId = null;
            if (String.isNotBlank(subcategory)) {
                List<Product_Subcategory__c> subs = [SELECT Id FROM Product_Subcategory__c WHERE Name = :subcategory LIMIT 1];
                if (!subs.isEmpty()) subcategoryId = subs[0].Id;
            }
            
            String baseWhere = 'IsActive = true';
            if (categoryId != null) baseWhere += ' AND Product_Category__c = :categoryId';
            if (subcategoryId != null) baseWhere += ' AND Product_Subcategory__c = :subcategoryId';
            if (onSaleOnly != null && onSaleOnly) baseWhere += ' AND Is_On_Sale__c = true';
            
            if (String.isNotBlank(availability)) {
                if (availability == 'En stock') {
                    baseWhere += ' AND Stock_Quantity__c > 0 AND (Availability__c = null OR Availability__c = \'\')';
                } else if (availability == 'Epuise') {
                    baseWhere += ' AND (Stock_Quantity__c = 0 OR Stock_Quantity__c = null) AND (Availability__c = null OR Availability__c = \'\')';
                } else {
                    baseWhere += ' AND Availability__c = :availability';
                }
            }
            
            String orderBy;
            if (sortBy == 'price_asc') orderBy = ' ORDER BY Name ASC';
            else if (sortBy == 'price_desc') orderBy = ' ORDER BY Name DESC';
            else if (sortBy == 'name_asc') orderBy = ' ORDER BY Name ASC';
            else if (sortBy == 'name_desc') orderBy = ' ORDER BY Name DESC';
            else orderBy = ' ORDER BY Rating__c DESC';
            
            String countQuery = 'SELECT COUNT() FROM Product2 WHERE ' + baseWhere;
            result.totalCount = Database.countQuery(countQuery);
            
            Integer offset = (pageNumber - 1) * pageSize;
            String query = 'SELECT Id, Name, Description, Image_URL__c, Rating__c, ' +
                'Stock_Quantity__c, Availability__c, Old_Price__c, Discount_Percent__c, Is_On_Sale__c, ' +
                'Product_Category__r.Name, Product_Subcategory__r.Name, ' +
                '(SELECT UnitPrice FROM PricebookEntries WHERE Pricebook2Id = :stdPB AND IsActive = true LIMIT 1) ' +
                'FROM Product2 WHERE ' + baseWhere + orderBy +
                ' LIMIT :pageSize OFFSET :offset';
            
            List<Product2> products = Database.query(query);
            
            for (Product2 p : products) {
                Decimal price = !p.PricebookEntries.isEmpty() ? p.PricebookEntries[0].UnitPrice : 0;
                if (minPrice != null && price < minPrice) continue;
                if (maxPrice != null && price > maxPrice) continue;
                
                CategoryProductData pd = new CategoryProductData();
                pd.id = p.Id;
                pd.name = p.Name;
                pd.price = '$' + price.setScale(2).toPlainString();
                pd.priceNum = price;
                pd.image = p.Image_URL__c;
                pd.description = p.Description;
                pd.category = p.Product_Category__r != null ? p.Product_Category__r.Name : '';
                pd.subcategory = p.Product_Subcategory__r != null ? p.Product_Subcategory__r.Name : '';
                pd.rating = p.Rating__c;
                pd.isOnSale = p.Is_On_Sale__c;
                
                if (p.Is_On_Sale__c && p.Old_Price__c != null) {
                    pd.oldPrice = '$' + p.Old_Price__c.setScale(2).toPlainString();
                    pd.discountPercent = p.Discount_Percent__c != null ? p.Discount_Percent__c.intValue() : 0;
                }
                
                if (String.isNotBlank(p.Availability__c)) {
                    pd.availability = p.Availability__c;
                    pd.availClass = p.Availability__c == 'En arrivage' ? 'avail-arriving' : 'avail-order';
                } else if (p.Stock_Quantity__c != null && p.Stock_Quantity__c > 0) {
                    pd.availability = 'En stock';
                    pd.availClass = 'avail-instock';
                } else {
                    pd.availability = 'Epuise';
                    pd.availClass = 'avail-out';
                }
                
                result.products.add(pd);
            }
            
            result.subcategories = new List<String>();
            if (categoryId != null) {
                for (Product_Subcategory__c sub : [
                    SELECT Name FROM Product_Subcategory__c
                    WHERE Product_Category__c = :categoryId AND Is_Active__c = true
                    ORDER BY Sort_Order__c ASC, Name ASC
                ]) {
                    result.subcategories.add(sub.Name);
                }
            }
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Datetime getHotDealsEndDate() {
        try {
            List<Site_Configuration__mdt> configs = [
                SELECT Value__c FROM Site_Configuration__mdt WHERE DeveloperName = 'Hot_Deals_End_Date' LIMIT 1
            ];
            return configs.isEmpty() ? null : configs[0].Value__c;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ═══ Helper Methods ═══
    
    private static ProductData buildProductData(Product2 p) {
        ProductData pd = new ProductData();
        pd.id = p.Id;
        pd.name = p.Name;
        pd.image = p.Image_URL__c;
        pd.description = p.Description;
        pd.category = p.Product_Category__r != null ? p.Product_Category__r.Name : '';
        pd.rating = p.Rating__c;
        Decimal price = (p.PricebookEntries != null && !p.PricebookEntries.isEmpty()) ? p.PricebookEntries[0].UnitPrice : 0;
        pd.price = '$' + price.setScale(2).toPlainString();
        pd.priceNum = price;
        return pd;
    }
    
    private static Map<Id, Decimal> getPriceMap(Set<Id> productIds, Id pricebookId) {
        Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice FROM PricebookEntry
            WHERE Product2Id IN :productIds AND Pricebook2Id = :pricebookId AND IsActive = true
        ]) {
            priceMap.put(pbe.Product2Id, pbe.UnitPrice);
        }
        return priceMap;
    }
    
    private static List<Decimal> parseEmbedding(String embeddingStr) {
        List<Decimal> vector = new List<Decimal>();
        for (String val : embeddingStr.split(',')) {
            vector.add(Decimal.valueOf(val.trim()));
        }
        return vector;
    }
    
    private static Decimal cosineSimilarity(List<Decimal> vecA, List<Decimal> vecB) {
        if (vecA.size() != vecB.size() || vecA.isEmpty()) return 0;
        Decimal dotProduct = 0, normA = 0, normB = 0;
        for (Integer i = 0; i < vecA.size(); i++) {
            dotProduct += vecA[i] * vecB[i];
            normA += vecA[i] * vecA[i];
            normB += vecB[i] * vecB[i];
        }
        Decimal denominator = Math.sqrt(normA.doubleValue()) * Math.sqrt(normB.doubleValue());
        if (denominator == 0) return 0;
        return dotProduct / denominator;
    }
    
    // ═══ Data Classes ═══
    
    public class ScoredProduct implements Comparable {
        public Product2 product;
        public Decimal score;
        public Integer compareTo(Object other) {
            ScoredProduct sp = (ScoredProduct) other;
            if (this.score > sp.score) return -1;
            if (this.score < sp.score) return 1;
            return 0;
        }
    }
    
    public class ProductData {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String price;
        @AuraEnabled public Decimal priceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal rating;
    }
    
    public class SearchResult {
        @AuraEnabled public List<ProductData> products;
        @AuraEnabled public Integer totalCount;
    }
    
    public class BestSellerData {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String price;
        @AuraEnabled public String image;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal rating;
        @AuraEnabled public Integer totalSold;
        @AuraEnabled public Integer rank;
        @AuraEnabled public Decimal priceNum; // ← ajouter
        
    }
    
    public class PromoProductData {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String newPrice;
        @AuraEnabled public String oldPrice;
        @AuraEnabled public Integer discountPercent;
        @AuraEnabled public Decimal priceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal rating;
    }
    
    public class BundleData {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String bundlePrice;
        @AuraEnabled public Decimal bundlePriceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String originalPrice;
        @AuraEnabled public String savings;
        @AuraEnabled public List<BundleItemData> items;
    }
    
    public class BundleItemData {
        @AuraEnabled public String id;
        @AuraEnabled public String productId;
        @AuraEnabled public String name;
        @AuraEnabled public String price;
        @AuraEnabled public Decimal priceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String category;
    }
    
    public class CategoryData {
        @AuraEnabled public String name;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<SubcategoryData> subcategories;
    }
    
    public class SubcategoryData {
        @AuraEnabled public String name;
        @AuraEnabled public Integer count;
    }
    
    public class CategoryCardData {
        @AuraEnabled public String name;
        @AuraEnabled public String image;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public String url;
    }
    
    public class CategoryPageResult {
        @AuraEnabled public List<CategoryProductData> products;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> subcategories;
    }
    
    public class CategoryProductData {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String price;
        @AuraEnabled public Decimal priceNum;
        @AuraEnabled public String image;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public String subcategory;
        @AuraEnabled public Decimal rating;
        @AuraEnabled public Boolean isOnSale;
        @AuraEnabled public String oldPrice;
        @AuraEnabled public Integer discountPercent;
        @AuraEnabled public String availability;
        @AuraEnabled public String availClass;
    }
}