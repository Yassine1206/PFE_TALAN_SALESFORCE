public without sharing class CkOrderController {
    
    // ── 1. Liste des commandes ────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<OrderSummary> getMyOrders() {
        try {
            String userId = System.UserInfo.getUserId();
            
            List<User> users = [
                SELECT ContactId FROM User WHERE Id = :userId LIMIT 1
            ];
            if (users.isEmpty() || users[0].ContactId == null) {
                return new List<OrderSummary>();
            }
            
            List<Contact> contacts = [
                SELECT AccountId FROM Contact
                WHERE Id = :users[0].ContactId LIMIT 1
                ];
            if (contacts.isEmpty() || contacts[0].AccountId == null) {
                return new List<OrderSummary>();
            }
            
            List<Order> orders = [
                SELECT Id, OrderNumber, EffectiveDate, Status,
                       Total_TTC__c, Payment_Method__c,
                       Shipping_City__c, Shipping_Country__c,
                       (SELECT Id FROM OrderItems)
                FROM Order
                WHERE AccountId = :contacts[0].AccountId
                ORDER BY EffectiveDate DESC
                ];
            
            List<OrderSummary> results = new List<OrderSummary>();
            for (Order o : orders) {
                OrderSummary s      = new OrderSummary();
                s.orderId           = o.Id;
                s.orderNumber       = o.OrderNumber;
                s.orderDate         = o.EffectiveDate != null
                    ? o.EffectiveDate.format() : '';
                s.status            = o.Status;
                s.totalTTC          = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
                s.paymentMethod     = o.Payment_Method__c;
                s.itemCount         = o.OrderItems != null ? o.OrderItems.size() : 0;
                s.shippingCity      = o.Shipping_City__c;
                s.shippingCountry   = o.Shipping_Country__c;
                results.add(s);
            }
            return results;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── 2. Détail d'une commande ──────────────────────────────
    @AuraEnabled(cacheable=true)
    public static OrderDetail getOrderDetail(String orderId) {
        try {
            Order o = [
                SELECT Id, OrderNumber, EffectiveDate, Status,
                       Subtotal__c, Tax_Amount__c, Shipping_Cost__c,
                       Discount__c, Total_TTC__c, Payment_Method__c,
                       Shipping_Address__c, Shipping_City__c,
                       Shipping_Country__c, Shipping_Zip__c,
                       Phone__c, Email__c, Promo_Code__c,
                       (SELECT Id, Product2Id, Product_Name_Text__c,
                               Product_Image__c, Quantity, UnitPrice,
                               TotalPrice
                        FROM OrderItems)
                FROM Order WHERE Id = :orderId LIMIT 1
            ];
            
            OrderDetail d       = new OrderDetail();
            d.orderId           = o.Id;
            d.orderNumber       = o.OrderNumber;
            d.orderDate         = o.EffectiveDate != null
                ? o.EffectiveDate.format() : '';
            d.status            = o.Status;
            d.subtotal          = o.Subtotal__c != null ? o.Subtotal__c : 0;
            d.taxAmount         = o.Tax_Amount__c != null ? o.Tax_Amount__c : 0;
            d.shippingCost      = o.Shipping_Cost__c != null ? o.Shipping_Cost__c : 0;
            d.discount          = o.Discount__c != null ? o.Discount__c : 0;
            d.totalTTC          = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
            d.paymentMethod     = o.Payment_Method__c;
            d.shippingAddress   = o.Shipping_Address__c;
            d.shippingCity      = o.Shipping_City__c;
            d.shippingCountry   = o.Shipping_Country__c;
            d.shippingZip       = o.Shipping_Zip__c;
            d.phone             = o.Phone__c;
            d.email             = o.Email__c;
            d.promoCode         = o.Promo_Code__c;
            
            // Invoice
            List<Invoice__c> invoices = [
                SELECT Id, Status__c, Tax_Rate__c
                FROM Invoice__c
                WHERE Order__c = :orderId LIMIT 1
            ];
            if (!invoices.isEmpty()) {
                d.invoiceStatus = invoices[0].Status__c;
                d.taxRate       = invoices[0].Tax_Rate__c != null
                    ? invoices[0].Tax_Rate__c : 0;
            }
            
            // Items
            d.items = new List<OrderItemDetail>();
            for (OrderItem oi : o.OrderItems) {
                OrderItemDetail item = new OrderItemDetail();
                item.itemId          = oi.Id;
                item.productId       = oi.Product2Id;
                item.name            = oi.Product_Name_Text__c;
                item.image           = oi.Product_Image__c;
                item.quantity        = Integer.valueOf(oi.Quantity);
                item.unitPrice       = oi.UnitPrice;
                item.totalPrice      = oi.TotalPrice;
                d.items.add(item);
            }
            
            return d;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── Wrappers ──────────────────────────────────────────────
    public class OrderSummary {
        @AuraEnabled public String  orderId;
        @AuraEnabled public String  orderNumber;
        @AuraEnabled public String  orderDate;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal totalTTC;
        @AuraEnabled public String  paymentMethod;
        @AuraEnabled public Integer itemCount;
        @AuraEnabled public String  shippingCity;
        @AuraEnabled public String  shippingCountry;
    }
    
    public class OrderDetail {
        @AuraEnabled public String  orderId;
        @AuraEnabled public String  orderNumber;
        @AuraEnabled public String  orderDate;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal taxRate;
        @AuraEnabled public Decimal shippingCost;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal totalTTC;
        @AuraEnabled public String  paymentMethod;
        @AuraEnabled public String  shippingAddress;
        @AuraEnabled public String  shippingCity;
        @AuraEnabled public String  shippingCountry;
        @AuraEnabled public String  shippingZip;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  email;
        @AuraEnabled public String  promoCode;
        @AuraEnabled public String  invoiceStatus;
        @AuraEnabled public List<OrderItemDetail> items;
    }
    
    public class OrderItemDetail {
        @AuraEnabled public String  itemId;
        @AuraEnabled public String  productId;
        @AuraEnabled public String  name;
        @AuraEnabled public String  image;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;
    }
}