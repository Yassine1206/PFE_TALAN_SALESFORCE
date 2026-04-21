public without sharing class CkCheckoutController {
    
    // ── 1. Données initiales ──────────────────────────────────
    @AuraEnabled
    public static CheckoutData getCheckoutData() {
        try {
            String userType = System.UserInfo.getUserType();
            if (userType == 'Guest') {
                CheckoutData data = new CheckoutData();
                data.isGuest = true;
                data.items   = new List<CheckoutItem>();
                return data;
            }
            
            String userId     = System.UserInfo.getUserId();
            CheckoutData data = new CheckoutData();
            data.isGuest      = false;
            
            User u = [
                SELECT Id, Email, Phone, FirstName, LastName,
                       City, Country, PostalCode, Street,
                       ContactId, Contact.AccountId
                FROM User WHERE Id = :userId LIMIT 1
            ];
            data.email      = u.Email;
            data.phone      = u.Phone;
            data.fullName   = u.FirstName + ' ' + u.LastName;
            data.street     = u.Street;
            data.city       = u.City;
            data.postalCode = u.PostalCode;
            data.country    = String.isBlank(u.Country) ? 'TN' : u.Country;
            data.accountId  = u.Contact != null ? u.Contact.AccountId : null;
            
            List<Cart__c> carts = [
                SELECT Id, Total__c,
                    (SELECT Id, Product_Name_c__c, Product_Image_c__c,
                            Product_Id_c__c, Unit_Price_c__c,
                            Quantity_c__c, Line_Total_c__c
                     FROM Cart_Items__r)
                FROM Cart__c
                WHERE User__c = :userId AND Status__c = 'Active'
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            
            data.items    = new List<CheckoutItem>();
            data.subtotal = 0;
            
            if (!carts.isEmpty()) {
                data.cartId = carts[0].Id;
                for (Cart_Item__c item : carts[0].Cart_Items__r) {
                    CheckoutItem ci = new CheckoutItem();
                    ci.itemId       = item.Id;
                    ci.productId    = item.Product_Id_c__c;
                    ci.name         = item.Product_Name_c__c;
                    ci.image        = item.Product_Image_c__c;
                    ci.unitPrice    = item.Unit_Price_c__c  != null ? item.Unit_Price_c__c  : 0;
                    ci.quantity     = item.Quantity_c__c   != null ? Integer.valueOf(item.Quantity_c__c) : 1;
                    ci.lineTotal    = item.Line_Total_c__c != null ? item.Line_Total_c__c : 0;
                    data.items.add(ci);
                    Decimal line = item.Line_Total_c__c != null
                        ? item.Line_Total_c__c
                        : (ci.unitPrice * ci.quantity);
                    data.subtotal += line;
                }
            }
            
            data.summary = CkTaxService.calculateSummary(data.subtotal, data.country, 0);
            return data;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── 2. Recalcul TVA ───────────────────────────────────────
    @AuraEnabled
    public static CkTaxService.CheckoutSummary recalculateTaxes(
        Decimal subtotal, String countryCode, Decimal discountAmount
    ) {
        try {
            return CkTaxService.calculateSummary(
                subtotal, countryCode,
            discountAmount != null ? discountAmount : 0
                );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── 3. Validation promo ───────────────────────────────────
    @AuraEnabled
    public static PromoResult validatePromoCode(String code, Decimal subtotal) {
        try {
            PromoResult result = new PromoResult();
            result.valid = false;
            
            if (String.isBlank(code)) {
                result.message = 'Please enter a promo code.';
                return result;
            }
            
            List<Promo_Code__c> promos = [
                SELECT Id, Code__c, Discount_Percent__c, Is_Active__c,
                       Max_Uses__c, Current_Uses__c, Expiry_Date__c
                FROM Promo_Code__c
                WHERE Code__c = :code.toUpperCase() LIMIT 1
            ];
            
            if (promos.isEmpty()) {
                result.message = 'Invalid promo code.'; return result;
            }
            Promo_Code__c promo = promos[0];
            if (!promo.Is_Active__c) {
                result.message = 'This promo code is no longer active.'; return result;
            }
            if (promo.Expiry_Date__c != null && promo.Expiry_Date__c < Date.today()) {
                result.message = 'This promo code has expired.'; return result;
            }
            if (promo.Max_Uses__c != null && promo.Current_Uses__c >= promo.Max_Uses__c) {
                result.message = 'This promo code has reached its usage limit.'; return result;
            }
            
            result.valid           = true;
            result.discountPercent = promo.Discount_Percent__c;
            result.discountAmount  = (subtotal * promo.Discount_Percent__c / 100).setScale(2);
            result.message         = promo.Discount_Percent__c.intValue() + '% discount applied!';
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── 4. Processus commande ─────────────────────────────────
    @AuraEnabled
    public static OrderResult processCheckout(CheckoutRequest req) {
        try {
            String paymentMethod = String.isBlank(req.paymentMethod) ? 'Card' : req.paymentMethod;
            String userId        = System.UserInfo.getUserId();
            Id stdPB             = [SELECT Id FROM Pricebook2
                                    WHERE IsStandard = true LIMIT 1].Id;
            
            List<Cart__c> carts = [
                SELECT Id, Total__c,
                    (SELECT Id, Product_Name_c__c, Product_Image_c__c,
                            Product_Id_c__c, Unit_Price_c__c,
                            Quantity_c__c, Line_Total_c__c
                     FROM Cart_Items__r)
                FROM Cart__c
                WHERE User__c = :userId AND Status__c = 'Active'
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            
            if (carts.isEmpty() || carts[0].Cart_Items__r.isEmpty()) {
                throw new AuraHandledException('Your cart is empty.');
            }
            
            Cart__c cart = carts[0];
            
            Decimal subtotal = 0;
            for (Cart_Item__c ci : cart.Cart_Items__r) {
                Decimal line = ci.Line_Total_c__c != null
                    ? ci.Line_Total_c__c
                    : (ci.Unit_Price_c__c != null && ci.Quantity_c__c != null
                    ? ci.Unit_Price_c__c * ci.Quantity_c__c : 0);
                subtotal += line;
            }
            
            Id accountId = findAccountId(userId);
            
            // Callout 1 : Vatstack
            CkTaxService.CheckoutSummary summary;
            try {
                summary = CkTaxService.calculateSummary(
                    subtotal,
                req.countryCode,
                req.discountAmount != null ? req.discountAmount : 0
                    );
            } catch (Exception e) {
                throw new AuraHandledException('Tax error: ' + e.getMessage());
            }
            
            // Callout 2 : Stripe
            String stripeUrl = null;
            if (paymentMethod == 'Card') {
                try {
                    String customerEmail = String.isNotBlank(req.email)
                        ? req.email
                        : UserInfo.getUserEmail();
                    stripeUrl = createStripeSession(summary.totalTTC, customerEmail);
                } catch (CalloutException e) {
                    throw new AuraHandledException('Stripe: ' + e.getMessage());
                } catch (Exception e) {
                    throw new AuraHandledException('Stripe unexpected: ' + e.getMessage());
                }
                if (String.isBlank(stripeUrl)) {
                    throw new AuraHandledException('Stripe returned empty URL');
                }
            }
            
            // DML après callouts
            accountId = getOrCreateAccountId(userId, accountId);
            Map<Id, Id> productToPBE = resolvePricebookEntries(cart.Cart_Items__r, stdPB);
            
            // FIX : Order déclaré AVANT les assignations
            Order ord               = new Order();
            ord.AccountId           = accountId;
            ord.EffectiveDate       = Date.today();
            ord.Status              = 'Draft';
            ord.Pricebook2Id        = stdPB;
            ord.Subtotal__c         = summary.subtotal;
            ord.Shipping_Cost__c    = summary.shippingCost;
            ord.Discount__c         = summary.discount;
            ord.Tax_Amount__c       = summary.taxAmount;
            ord.Total_TTC__c        = summary.totalTTC;
            ord.Order_Total__c      = summary.totalTTC;
            ord.Payment_Method__c   = paymentMethod;
            ord.Shipping_Address__c = req.street;
            ord.Shipping_City__c    = req.city;
            ord.Shipping_Country__c = req.countryCode;
            ord.Shipping_Zip__c     = req.postalCode;
            ord.Phone__c            = req.phone;
            ord.Email__c            = req.email;
            ord.Promo_Code__c       = req.promoCode;
            // FIX : champs standard directement avec req.countryCode
            // State & Country picklists désactivées → string libre acceptée
            ord.ShippingStreet      = req.street;
            ord.ShippingCity        = req.city;
            ord.ShippingPostalCode  = req.postalCode;
            ord.ShippingCountry     = req.countryCode;
            insert ord;
            
            List<OrderItem> orderItems = new List<OrderItem>();
            for (Cart_Item__c ci : cart.Cart_Items__r) {
                Id prodId = Id.valueOf(ci.Product_Id_c__c);
                Id pbeId  = productToPBE.get(prodId);
                if (pbeId == null) continue;
                Decimal unitPrice = ci.Unit_Price_c__c != null ? ci.Unit_Price_c__c : 0;
                Decimal qty       = ci.Quantity_c__c   != null ? ci.Quantity_c__c   : 1;
                if (unitPrice <= 0) continue;
                OrderItem oi            = new OrderItem();
                oi.OrderId              = ord.Id;
                oi.Product2Id           = prodId;
                oi.PricebookEntryId     = pbeId;
                oi.Quantity             = qty;
                oi.UnitPrice            = unitPrice;
                oi.Product_Image__c     = ci.Product_Image_c__c;
                oi.Product_Name_Text__c = ci.Product_Name_c__c;
                orderItems.add(oi);
            }
            if (orderItems.isEmpty()) {
                delete ord;
                throw new AuraHandledException('Unable to create order items.');
            }
            insert orderItems;
            
            ord.Status = 'Activated';
            update ord;
            
            Invoice__c inv        = new Invoice__c();
            inv.Order__c          = ord.Id;
            inv.Subtotal__c       = summary.subtotal;
            inv.Tax_Amount__c     = summary.taxAmount;
            inv.Tax_Rate__c       = summary.taxRate;
            inv.Shipping_Cost__c  = summary.shippingCost;
            inv.Discount__c       = summary.discount;
            inv.Total_TTC__c      = summary.totalTTC;
            inv.Payment_Method__c = paymentMethod;
            inv.Country_Code__c   = req.countryCode;
            inv.Status__c         = 'Draft';
            insert inv;
            
            if (String.isNotBlank(req.promoCode)) {
                List<Promo_Code__c> promos = [
                    SELECT Id, Current_Uses__c FROM Promo_Code__c
                    WHERE Code__c = :req.promoCode LIMIT 1
                ];
                if (!promos.isEmpty()) {
                    promos[0].Current_Uses__c += 1;
                    update promos;
                }
            }
            
            OrderResult result   = new OrderResult();
            result.success       = true;
            result.orderId       = ord.Id;
            result.orderNumber   = ord.OrderNumber;
            result.paymentMethod = paymentMethod;
            result.totalTTC      = summary.totalTTC;
            
            if (paymentMethod == 'COD') {
                ord.Status    = 'Awaiting Delivery Payment';
                update ord;
                inv.Status__c = 'Sent';
                update inv;
                cart.Status__c = 'Completed';
                update cart;
                result.redirectUrl = '/s/order-confirmation?orderId='
                    + ord.Id + '&method=COD';
            } else {
                result.redirectUrl = stripeUrl + ':::' + ord.Id;
            }
            
            return result;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'processCheckout [' + e.getTypeName() + ']: ' + e.getMessage()
                );
        }
    }
    
    // ── 5. Confirm Order ─────────────────────────────────────
    public class ConfirmResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  orderNumber;
        @AuraEnabled public Decimal totalTTC;
        @AuraEnabled public String  paymentMethod;
        @AuraEnabled public String  shippingCity;
        @AuraEnabled public String  shippingCountry;
        @AuraEnabled public String  orderDate;
    }
    
    @AuraEnabled
    public static ConfirmResult confirmOrder(String orderId, String sessionId) {
        try {
            API_Config__mdt config = [
                SELECT API_Key__c FROM API_Config__mdt
                WHERE DeveloperName = 'Stripe' LIMIT 1
            ];
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.stripe.com/v1/checkout/sessions/' + sessionId);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + config.API_Key__c);
            req.setTimeout(15000);
            
            HttpResponse res = new Http().send(req);
            
            ConfirmResult result = new ConfirmResult();
            result.success = false;
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> session =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String paymentStatus = (String) session.get('payment_status');
                
                if (paymentStatus == 'paid') {
                    String userId = System.UserInfo.getUserId();
                    
                    if (String.isBlank(orderId)) {
                        Id accountId = null;
                        List<User> users = [
                            SELECT ContactId FROM User
                            WHERE Id = :userId AND ContactId != null LIMIT 1
                        ];
                        if (!users.isEmpty()) {
                            List<Contact> contacts = [
                                SELECT AccountId FROM Contact
                                WHERE Id = :users[0].ContactId LIMIT 1
                                ];
                            if (!contacts.isEmpty()) accountId = contacts[0].AccountId;
                        }
                        if (accountId != null) {
                            List<Order> orders = [
                                SELECT Id FROM Order
                                WHERE Status = 'Activated'
                                AND AccountId = :accountId
                                ORDER BY CreatedDate DESC LIMIT 1
                            ];
                            if (!orders.isEmpty()) orderId = orders[0].Id;
                        }
                    }
                    
                    if (String.isBlank(orderId)) {
                        List<Order> orders = [
                            SELECT Id FROM Order
                            WHERE Status = 'Activated'
                            ORDER BY CreatedDate DESC LIMIT 1
                        ];
                        if (!orders.isEmpty()) orderId = orders[0].Id;
                    }
                    
                    if (String.isBlank(orderId)) return result;
                    
                    Order ord = [
                        SELECT Id, OrderNumber, Total_TTC__c, Payment_Method__c,
                               ShippingCity, ShippingCountry,
                               Shipping_City__c, Shipping_Country__c,
                               EffectiveDate
                        FROM Order WHERE Id = :orderId LIMIT 1
                    ];
                    ord.Status               = 'Paid';
                    ord.Stripe_Payment_Id__c = sessionId;
                    update ord;
                    
                    List<Invoice__c> invList = [
                        SELECT Id FROM Invoice__c
                        WHERE Order__c = :orderId LIMIT 1
                    ];
                    if (!invList.isEmpty()) {
                        invList[0].Status__c = 'Paid';
                        update invList;
                    }
                    
                    List<Cart__c> carts = [
                        SELECT Id FROM Cart__c
                        WHERE User__c = :userId AND Status__c = 'Active' LIMIT 1
                    ];
                    if (!carts.isEmpty()) {
                        carts[0].Status__c = 'Completed';
                        update carts;
                    }
                    
                    // Utiliser champs custom si standard vides
                    String city    = String.isNotBlank(ord.ShippingCity)
                        ? ord.ShippingCity    : ord.Shipping_City__c;
                    String country = String.isNotBlank(ord.ShippingCountry)
                        ? ord.ShippingCountry : ord.Shipping_Country__c;
                    
                    result.success         = true;
                    result.orderNumber     = ord.OrderNumber;
                    result.totalTTC        = ord.Total_TTC__c;
                    result.paymentMethod   = ord.Payment_Method__c;
                    result.shippingCity    = city;
                    result.shippingCountry = country;
                    result.orderDate       = ord.EffectiveDate != null
                        ? ord.EffectiveDate.format() : '';
                }
            }
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── Helpers ───────────────────────────────────────────────
    private static Id findAccountId(String userId) {
        List<User> users = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
        if (!users.isEmpty() && users[0].ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId FROM Contact
                WHERE Id = :users[0].ContactId LIMIT 1
                ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                return contacts[0].AccountId;
            }
        }
        List<Account> accts = [
            SELECT Id FROM Account WHERE Name = 'TalFlow Customers' LIMIT 1
        ];
        return accts.isEmpty() ? null : accts[0].Id;
    }
    
    private static Id getOrCreateAccountId(String userId, Id existingId) {
        if (existingId != null) return existingId;
        Account a = new Account(Name = 'TalFlow Customers');
        insert a;
        return a.Id;
    }
    
    private static Map<Id, Id> resolvePricebookEntries(
        List<Cart_Item__c> cartItems, Id stdPB
    ) {
        Set<Id> productIds = new Set<Id>();
        for (Cart_Item__c ci : cartItems) productIds.add(Id.valueOf(ci.Product_Id_c__c));
        
        Map<Id, Id> productToPBE = new Map<Id, Id>();
        List<PricebookEntry> existingPBEs = [
            SELECT Id, Product2Id, IsActive FROM PricebookEntry
            WHERE Product2Id IN :productIds AND Pricebook2Id = :stdPB
        ];
        
        List<PricebookEntry> toActivate = new List<PricebookEntry>();
        for (PricebookEntry pbe : existingPBEs) {
            productToPBE.put(pbe.Product2Id, pbe.Id);
            if (!pbe.IsActive) { pbe.IsActive = true; toActivate.add(pbe); }
        }
        if (!toActivate.isEmpty()) update toActivate;
        
        List<PricebookEntry> newPBEs = new List<PricebookEntry>();
        for (Cart_Item__c ci : cartItems) {
            Id prodId = Id.valueOf(ci.Product_Id_c__c);
            if (!productToPBE.containsKey(prodId)) {
                newPBEs.add(new PricebookEntry(
                    Pricebook2Id = stdPB,
                Product2Id   = prodId,
                UnitPrice    = ci.Unit_Price_c__c,
                IsActive     = true
                    ));
            }
        }
        if (!newPBEs.isEmpty()) {
            insert newPBEs;
            for (PricebookEntry pbe : newPBEs) productToPBE.put(pbe.Product2Id, pbe.Id);
        }
        return productToPBE;
    }
    
    private static String createStripeSession(Decimal total, String email) {
        if (total == null || total <= 0) {
            throw new CalloutException('Total invalide: ' + total);
        }
        
        List<API_Config__mdt> configs = [
            SELECT API_Key__c FROM API_Config__mdt
            WHERE DeveloperName = 'Stripe' LIMIT 1
        ];
        
        if (configs.isEmpty() || String.isBlank(configs[0].API_Key__c)) {
            throw new CalloutException('Stripe API key manquante dans API_Config__mdt');
        }
        
        Integer amountInCents = Integer.valueOf(total.setScale(2) * 100);
        
        String successUrl = 'https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com/TalFlowExpress/s/order-confirmation?session_id={CHECKOUT_SESSION_ID}';
        String cancelUrl  = 'https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com/TalFlowExpress/s/checkout';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.stripe.com/v1/checkout/sessions');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + configs[0].API_Key__c);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(15000);
        req.setBody(
            'mode=payment'
            + '&success_url=' + EncodingUtil.urlEncode(successUrl, 'UTF-8')
            + '&cancel_url='  + EncodingUtil.urlEncode(cancelUrl, 'UTF-8')
            + (String.isNotBlank(email) && email.contains('@')
            ? '&customer_email=' + EncodingUtil.urlEncode(email, 'UTF-8') : '')
            + '&line_items[0][price_data][currency]=usd'
            + '&line_items[0][price_data][unit_amount]=' + amountInCents
            + '&line_items[0][price_data][product_data][name]='
            + EncodingUtil.urlEncode('TalFlow Express Order', 'UTF-8')
            + '&line_items[0][quantity]=1'
            );
        
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> session =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String url = (String) session.get('url');
            if (String.isBlank(url)) {
                throw new CalloutException('Stripe URL null. Body: ' + res.getBody().left(500));
            }
            return url;
        }
        
        throw new CalloutException(
            'Stripe HTTP ' + res.getStatusCode() + ': ' + res.getBody().left(500)
            );
    }
    
    // ── Wrappers ──────────────────────────────────────────────
    public class CheckoutData {
        @AuraEnabled public Boolean  isGuest;
        @AuraEnabled public String   cartId;
        @AuraEnabled public String   email;
        @AuraEnabled public String   phone;
        @AuraEnabled public String   fullName;
        @AuraEnabled public String   street;
        @AuraEnabled public String   city;
        @AuraEnabled public String   postalCode;
        @AuraEnabled public String   country;
        @AuraEnabled public String   accountId;
        @AuraEnabled public List<CheckoutItem> items;
        @AuraEnabled public Decimal  subtotal;
        @AuraEnabled public CkTaxService.CheckoutSummary summary;
    }
    
    public class CheckoutItem {
        @AuraEnabled public String  itemId;
        @AuraEnabled public String  productId;
        @AuraEnabled public String  name;
        @AuraEnabled public String  image;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal lineTotal;
    }
    
    public class CheckoutRequest {
        @AuraEnabled public String  street;
        @AuraEnabled public String  city;
        @AuraEnabled public String  postalCode;
        @AuraEnabled public String  countryCode;
        @AuraEnabled public String  email;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  paymentMethod;
        @AuraEnabled public Decimal discountAmount;
        @AuraEnabled public String  promoCode;
    }
    
    public class PromoResult {
        @AuraEnabled public Boolean valid;
        @AuraEnabled public String  message;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Decimal discountAmount;
    }
    
    public class OrderResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id      orderId;
        @AuraEnabled public String  orderNumber;
        @AuraEnabled public String  paymentMethod;
        @AuraEnabled public Decimal totalTTC;
        @AuraEnabled public String  redirectUrl;
        @AuraEnabled public String  errorMessage;
    }
}