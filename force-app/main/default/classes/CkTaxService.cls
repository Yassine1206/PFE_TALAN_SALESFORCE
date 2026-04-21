public with sharing class CkTaxService {
    
    private static final Map<String, Decimal> SHIPPING_COSTS = new Map<String, Decimal>{
        'TN' => 7.0,  'FR' => 15.0, 'DE' => 20.0,
        'IT' => 20.0, 'ES' => 20.0, 'GB' => 18.0,
        'US' => 35.0, 'CA' => 30.0, 'AU' => 40.0,
        'MA' => 10.0, 'DZ' => 10.0, 'SA' => 25.0,
        'AE' => 25.0, 'TR' => 20.0, 'EG' => 15.0
    };
    
    private static final Map<String, String> DELIVERY_DAYS = new Map<String, String>{
        'TN' => '1-3', 'FR' => '3-5', 'DE' => '5-7',
        'IT' => '5-7', 'ES' => '5-7', 'GB' => '4-6',
        'US' => '7-14','CA' => '7-14','AU' => '10-20',
        'MA' => '2-4', 'DZ' => '2-4', 'SA' => '5-8',
        'AE' => '5-8', 'TR' => '5-8', 'EG' => '5-8'
    };
    
    public static Decimal getShippingCost(String cc) {
        return SHIPPING_COSTS.containsKey(cc) ? SHIPPING_COSTS.get(cc) : 40;
    }
    
    public static String getDeliveryDays(String cc) {
        return (DELIVERY_DAYS.containsKey(cc)
            ? DELIVERY_DAYS.get(cc) : '10-21') + ' business days';
    }
    
    @AuraEnabled
    public static CheckoutSummary calculateSummary(
        Decimal subtotal,
    String  countryCode,
    Decimal discountAmount
    ) {
        CkVatstackService.VatstackResult vatResult =
            CkVatstackService.getTaxRate(countryCode);
        
        Decimal taxRate    = vatResult.taxRate;
        Decimal shipping   = getShippingCost(countryCode);
        Decimal discount   = discountAmount == null ? 0 : discountAmount;
        Decimal taxAmount  = ((subtotal - discount) * taxRate / 100).setScale(2);
        Decimal totalTTC   = (subtotal - discount + taxAmount + shipping).setScale(2);
        
        CheckoutSummary s  = new CheckoutSummary();
        s.subtotal         = subtotal;
        s.discount         = discount;
        s.taxRate          = taxRate;
        s.taxAmount        = taxAmount;
        s.shippingCost     = shipping;
        s.totalTTC         = totalTTC;
        s.deliveryDays     = getDeliveryDays(countryCode);
        s.countryCode      = countryCode;
        s.isFallbackRate   = vatResult.isFallback;
        return s;
    }
    
    public class CheckoutSummary {
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal taxRate;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal shippingCost;
        @AuraEnabled public Decimal totalTTC;
        @AuraEnabled public String  deliveryDays;
        @AuraEnabled public String  countryCode;
        @AuraEnabled public Boolean isFallbackRate;
    }
}