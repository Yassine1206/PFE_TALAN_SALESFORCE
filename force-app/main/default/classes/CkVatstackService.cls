public with sharing class CkVatstackService {
    
    private static String getApiKey() {
        List<API_Config__mdt> configs = [
            SELECT API_Key__c FROM API_Config__mdt
            WHERE DeveloperName = 'Vatstack' AND Is_Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) throw new CkVatstackException('Vatstack API key not configured');
        return configs[0].API_Key__c;
    }
    
    @AuraEnabled
    public static VatstackResult getTaxRate(String countryCode) {
        try {
            String apiKey = getApiKey();
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.vatstack.com/v1/rates?country_code=' + countryCode);
            req.setMethod('GET');
            req.setHeader('X-API-KEY', apiKey);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);
            
            HttpResponse res = new Http().send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> body =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                List<Object> rates = (List<Object>) body.get('rates');
                
                if (rates != null && !rates.isEmpty()) {
                    // Prendre le premier objet rates
                    Map<String, Object> rateObj = (Map<String, Object>) rates[0];
                    
                    // Vatstack structure :
                    // rates[0].categories.eservice → taux standard pour services numériques
                    // rates[0].categories.broadcasting → autre taux standard
                    // On prend eservice qui correspond au taux TVA standard digital
                    Map<String, Object> categories =
                        (Map<String, Object>) rateObj.get('categories');
                    
                    if (categories != null) {
                        // Priorité : eservice → broadcasting → telecommunication
                        // Ces 3 correspondent au taux TVA standard dans l'UE
                        Decimal taxRate = 0;
                        
                        if (categories.get('eservice') != null) {
                            taxRate = Decimal.valueOf(
                                String.valueOf(categories.get('eservice'))
                                );
                        } else if (categories.get('broadcasting') != null) {
                            taxRate = Decimal.valueOf(
                                String.valueOf(categories.get('broadcasting'))
                                );
                        } else if (categories.get('telecommunication') != null) {
                            taxRate = Decimal.valueOf(
                                String.valueOf(categories.get('telecommunication'))
                                );
                        }
                        
                        VatstackResult result = new VatstackResult();
                        result.success     = true;
                        result.countryCode = countryCode;
                        result.taxRate     = taxRate;
                        result.isFallback  = false;
                        return result;
                    }
                }
                
                // Pays non couvert (TN, MA, etc.) → fallback
                return getFallbackRate(countryCode);
            }
            return getFallbackRate(countryCode);
            
        } catch (Exception e) {
            return getFallbackRate(countryCode);
        }
    }
    
    private static VatstackResult getFallbackRate(String countryCode) {
        Map<String, Decimal> fallback = new Map<String, Decimal>{
            'TN' => 19.0, 'MA' => 20.0, 'DZ' => 19.0,
            'US' => 0.0,  'CA' => 5.0,  'AU' => 10.0,
            'SA' => 15.0, 'AE' => 5.0,  'EG' => 14.0,
            'TR' => 18.0
        };
        VatstackResult result = new VatstackResult();
        result.success        = true;
        result.countryCode    = countryCode;
        result.taxRate        = fallback.containsKey(countryCode)
            ? fallback.get(countryCode) : 0;
        result.isFallback     = true;
        return result;
    }
    
    public class VatstackResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  countryCode;
        @AuraEnabled public Decimal taxRate;
        @AuraEnabled public Boolean isFallback = false;
    }
    
    public class CkVatstackException extends Exception {}
}