public without sharing class CkEmbeddingService {
    
    @InvocableMethod(label='Generate Embeddings' description='Generates embeddings for products')
    public static void generateEmbeddings(List<Id> productIds) {
        for (Id pid : productIds) {
            if (System.isFuture() || System.isBatch() || System.isQueueable()) {
                // Already in async context, run synchronously
                generateEmbeddingSync(pid);
            } else {
                generateEmbeddingAsync(pid);
            }
        }
    }
    
    @future(callout=true)
    public static void generateEmbeddingAsync(Id productId) {
        generateEmbeddingSync(productId);
    }
    
    public static void generateEmbeddingSync(Id productId) {
        try {
            Product2 product = [
                SELECT Id, Name, Description, Product_Category__r.Name
                FROM Product2 WHERE Id = :productId LIMIT 1
            ];
            
            String inputText = product.Name + ' ' + 
                (product.Product_Category__r != null ? product.Product_Category__r.Name : '') + ' ' + 
                (product.Description != null ? product.Description : '');
            
            API_Config__mdt config = [SELECT API_Key__c FROM API_Config__mdt WHERE DeveloperName = 'Gemini' LIMIT 1];
            
            String endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=' + config.API_Key__c;
            
            Map<String, Object> content = new Map<String, Object>();
            List<Map<String, String>> parts = new List<Map<String, String>>();
            Map<String, String> part = new Map<String, String>();
            part.put('text', inputText);
            parts.add(part);
            content.put('parts', parts);
            
            Map<String, Object> body = new Map<String, Object>();
            body.put('model', 'models/gemini-embedding-001');
            body.put('content', content);
            body.put('outputDimensionality', 50);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);
            req.setBody(JSON.serialize(body));
            
            HttpResponse res = new Http().send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> embedding = (Map<String, Object>) response.get('embedding');
                if (embedding == null) return;
                
                List<Object> values = (List<Object>) embedding.get('values');
                if (values == null || values.isEmpty()) return;
                
                List<String> strValues = new List<String>();
                for (Object val : values) {
                    strValues.add(String.valueOf((Decimal) val));
                }
                
                product.Embedding__c = String.join(strValues, ',');
                update product;
                System.debug('Embedding generated for: ' + product.Name);
            } else {
                System.debug('API Error: ' + res.getStatusCode() + ' - ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Embedding generation failed: ' + e.getMessage());
        }
    }
    
    public static void regenerateAllEmbeddings() {
        List<Product2> products = [SELECT Id FROM Product2 WHERE IsActive = true];
        for (Product2 p : products) {
            generateEmbeddingAsync(p.Id);
        }
    }
}