public without sharing class CkCheckoutController {
  // ── 1. Données initiales ──────────────────────────────────
  @AuraEnabled
  public static CheckoutData getCheckoutData() {
    try {
      String userType = System.UserInfo.getUserType();
      if (userType == 'Guest') {
        CheckoutData data = new CheckoutData();
        data.isGuest = true;
        data.items = new List<CheckoutItem>();
        return data;
      }

      String userId = System.UserInfo.getUserId();
      CheckoutData data = new CheckoutData();
      data.isGuest = false;

      User u = [
        SELECT
          Id,
          Email,
          Phone,
          FirstName,
          LastName,
          Street,
          City,
          State,
          PostalCode,
          Country,
          ContactId,
          Contact.AccountId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      data.email = u.Email;
      data.phone = u.Phone;
      data.fullName = u.FirstName + ' ' + u.LastName;
      data.street = u.Street;
      data.city = u.City;
      data.state = u.State;
      data.postalCode = u.PostalCode;
      data.country = getCountryCode(u.Country);
      data.accountId = u.Contact != null ? u.Contact.AccountId : null;

      List<Cart__c> carts = [
        SELECT
          Id,
          Total__c,
          (
            SELECT
              Id,
              Product_Name_c__c,
              Product_Image_c__c,
              Product_Id_c__c,
              Unit_Price_c__c,
              Quantity_c__c,
              Line_Total_c__c
            FROM Cart_Items__r
          )
        FROM Cart__c
        WHERE User__c = :userId AND Status__c = 'Active'
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];

      data.items = new List<CheckoutItem>();
      data.subtotal = 0;

      if (!carts.isEmpty()) {
        data.cartId = carts[0].Id;
        for (Cart_Item__c item : carts[0].Cart_Items__r) {
          CheckoutItem ci = new CheckoutItem();
          ci.itemId = item.Id;
          ci.productId = item.Product_Id_c__c;
          ci.name = item.Product_Name_c__c;
          ci.image = item.Product_Image_c__c;
          ci.unitPrice = item.Unit_Price_c__c != null
            ? item.Unit_Price_c__c
            : 0;
          ci.quantity = item.Quantity_c__c != null
            ? Integer.valueOf(item.Quantity_c__c)
            : 1;
          ci.lineTotal = item.Line_Total_c__c != null
            ? item.Line_Total_c__c
            : 0;
          data.items.add(ci);
          data.subtotal += ci.lineTotal > 0
            ? ci.lineTotal
            : (ci.unitPrice * ci.quantity);
        }
      }

      data.summary = CkTaxService.calculateSummary(
        data.subtotal,
        data.country,
        0
      );
      return data;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 2. Recalcul TVA ───────────────────────────────────────
  @AuraEnabled
  public static CkTaxService.CheckoutSummary recalculateTaxes(
    Decimal subtotal,
    String countryCode,
    Decimal discountAmount
  ) {
    try {
      return CkTaxService.calculateSummary(
        subtotal,
        countryCode,
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
        SELECT
          Id,
          Code__c,
          Discount_Percent__c,
          Is_Active__c,
          Max_Uses__c,
          Current_Uses__c,
          Expiry_Date__c
        FROM Promo_Code__c
        WHERE Code__c = :code.toUpperCase()
        LIMIT 1
      ];

      if (promos.isEmpty()) {
        result.message = 'Invalid promo code.';
        return result;
      }
      Promo_Code__c promo = promos[0];
      if (!promo.Is_Active__c) {
        result.message = 'This promo code is no longer active.';
        return result;
      }
      if (promo.Expiry_Date__c != null && promo.Expiry_Date__c < Date.today()) {
        result.message = 'This promo code has expired.';
        return result;
      }
      if (
        promo.Max_Uses__c != null &&
        promo.Current_Uses__c >= promo.Max_Uses__c
      ) {
        result.message = 'This promo code has reached its usage limit.';
        return result;
      }

      result.valid = true;
      result.discountPercent = promo.Discount_Percent__c;
      result.discountAmount = (subtotal *
        promo.Discount_Percent__c /
        100)
        .setScale(2);
      result.message =
        promo.Discount_Percent__c.intValue() + '% discount applied!';
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 4. Process Checkout ───────────────────────────────────
  @AuraEnabled
  public static OrderResult processCheckout(
    String street,
    String city,
    String state,
    String postalCode,
    String countryCode,
    String email,
    String phone,
    String paymentMethod,
    Decimal discountAmount,
    String promoCode
  ) {
    try {
      String reqStreet = street;
      String reqCity = city;
      String reqState = state;
      String reqPostalCode = postalCode;
      String reqCountryCode = countryCode;
      String reqEmail = email;
      String reqPhone = phone;
      String reqPromoCode = promoCode;
      Decimal reqDiscount = discountAmount != null ? discountAmount : 0;
      String resolvedPaymentMethod = String.isBlank(paymentMethod)
        ? 'Card'
        : paymentMethod;

      String userId = System.UserInfo.getUserId();
      Id stdPB = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE
        LIMIT 1
      ]
      .Id;

      List<Cart__c> carts = [
        SELECT
          Id,
          Total__c,
          (
            SELECT
              Id,
              Product_Name_c__c,
              Product_Image_c__c,
              Product_Id_c__c,
              Unit_Price_c__c,
              Quantity_c__c,
              Line_Total_c__c
            FROM Cart_Items__r
          )
        FROM Cart__c
        WHERE User__c = :userId AND Status__c = 'Active'
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];

      if (carts.isEmpty() || carts[0].Cart_Items__r.isEmpty()) {
        throw new AuraHandledException('Your cart is empty.');
      }

      Cart__c cart = carts[0];
      Decimal subtotal = 0;
      for (Cart_Item__c ci : cart.Cart_Items__r) {
        subtotal += ci.Line_Total_c__c != null
          ? ci.Line_Total_c__c
          : (ci.Unit_Price_c__c != null &&
              ci.Quantity_c__c != null
              ? ci.Unit_Price_c__c * ci.Quantity_c__c
              : 0);
      }

      Id accountId = findAccountId(userId);

      // Callout TVA
      CkTaxService.CheckoutSummary summary;
      try {
        summary = CkTaxService.calculateSummary(
          subtotal,
          reqCountryCode,
          reqDiscount
        );
      } catch (Exception e) {
        throw new AuraHandledException('Tax error: ' + e.getMessage());
      }

      accountId = getOrCreateAccountId(userId, accountId);

      // Mise à jour de l'Account uniquement si l'adresse est fournie
      if (
        accountId != null &&
        String.isNotBlank(reqStreet) &&
        String.isNotBlank(reqCity)
      ) {
        Account acc = new Account(Id = accountId);
        acc.ShippingStreet = reqStreet;
        acc.ShippingCity = reqCity;
        acc.ShippingPostalCode = reqPostalCode;
        acc.ShippingCountryCode = reqCountryCode;
        try {
          update acc;
        } catch (Exception e) {
          throw new AuraHandledException(
            'Account update failed: ' + e.getMessage()
          );
        }
      } else {
        System.debug(
          '⚠️ Address skipped: street=' +
            reqStreet +
            ', city=' +
            reqCity +
            ', country=' +
            reqCountryCode +
            ' — frontend did not send values'
        );
      }

      Map<Id, Id> productToPBE = resolvePricebookEntries(
        cart.Cart_Items__r,
        stdPB
      );

      // Create order — uniquement champs STANDARDS
      Order ord = new Order();
      ord.AccountId = accountId;
      ord.EffectiveDate = Date.today();
      ord.Status = 'Draft';
      ord.Pricebook2Id = stdPB;
      ord.Subtotal__c = summary.subtotal;
      ord.Shipping_Cost__c = summary.shippingCost;
      ord.Discount__c = summary.discount;
      ord.Tax_Amount__c = summary.taxAmount;
      ord.Total_TTC__c = summary.totalTTC;
      ord.Order_Total__c = summary.totalTTC;
      ord.Payment_Method__c = resolvedPaymentMethod;
      ord.Phone__c = reqPhone;
      ord.Email__c = reqEmail;
      ord.Promo_Code__c = reqPromoCode;

      // Champs STANDARDS Salesforce — ShippingCountry sera rempli automatiquement
      // par Salesforce à partir de ShippingCountryCode (State/Country Picklists activés)
      ord.ShippingStreet = reqStreet;
      ord.ShippingCity = reqCity;
      // ord.ShippingState = reqState;   // décommenter si State Picklist activée
      ord.ShippingPostalCode = reqPostalCode;
      ord.ShippingCountryCode = reqCountryCode;

      insert ord;

      List<OrderItem> orderItems = new List<OrderItem>();
      for (Cart_Item__c ci : cart.Cart_Items__r) {
        Id prodId = Id.valueOf(ci.Product_Id_c__c);
        Id pbeId = productToPBE.get(prodId);
        if (pbeId == null)
          continue;
        Decimal unitPrice = ci.Unit_Price_c__c != null ? ci.Unit_Price_c__c : 0;
        Decimal qty = ci.Quantity_c__c != null ? ci.Quantity_c__c : 1;
        if (unitPrice <= 0)
          continue;
        OrderItem oi = new OrderItem();
        oi.OrderId = ord.Id;
        oi.Product2Id = prodId;
        oi.PricebookEntryId = pbeId;
        oi.Quantity = qty;
        oi.UnitPrice = unitPrice;
        oi.Product_Image__c = ci.Product_Image_c__c;
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

      Invoice__c inv = new Invoice__c();
      inv.Order__c = ord.Id;
      inv.Subtotal__c = summary.subtotal;
      inv.Tax_Amount__c = summary.taxAmount;
      inv.Tax_Rate__c = summary.taxRate;
      inv.Shipping_Cost__c = summary.shippingCost;
      inv.Discount__c = summary.discount;
      inv.Total_TTC__c = summary.totalTTC;
      inv.Payment_Method__c = resolvedPaymentMethod;
      inv.Country_Code__c = reqCountryCode;
      inv.Status__c = 'Draft';
      insert inv;

      if (String.isNotBlank(reqPromoCode)) {
        List<Promo_Code__c> promos = [
          SELECT Id, Current_Uses__c
          FROM Promo_Code__c
          WHERE Code__c = :reqPromoCode
          LIMIT 1
        ];
        if (!promos.isEmpty()) {
          promos[0].Current_Uses__c += 1;
          update promos;
        }
      }

      OrderResult result = new OrderResult();
      result.success = true;
      result.orderId = ord.Id;
      result.orderNumber = ord.OrderNumber;
      result.paymentMethod = resolvedPaymentMethod;
      result.totalTTC = summary.totalTTC;

      if (resolvedPaymentMethod == 'COD') {
        ord.Status = 'Pending';
        update ord;
        inv.Status__c = 'Sent';
        update inv;
        cart.Status__c = 'Completed';
        update cart;
        result.redirectUrl =
          '/s/order-confirmation?orderId=' +
          ord.Id +
          '&method=COD';
      } else {
        result.redirectUrl = 'PENDING_STRIPE:::' + ord.Id;
      }

      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'TYPE: ' +
          e.getTypeName() +
          ' | MSG: ' +
          e.getMessage() +
          ' | LINE: ' +
          e.getStackTraceString()
      );
    }
  }

  // ── 5. Créer session Stripe ───────────────────────────────
  @AuraEnabled
  public static String createStripeSessionWithOrder(
    String orderId,
    Decimal total,
    String email
  ) {
    try {
      if (total == null || total <= 0) {
        throw new AuraHandledException('Invalid total: ' + total);
      }

      List<API_Config__mdt> configs = [
        SELECT API_Key__c
        FROM API_Config__mdt
        WHERE DeveloperName = 'Stripe'
        LIMIT 1
      ];
      if (configs.isEmpty() || String.isBlank(configs[0].API_Key__c)) {
        throw new AuraHandledException('Stripe API key missing.');
      }

      Integer amountInCents = Integer.valueOf(total.setScale(2) * 100);
      String successUrl =
        'https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com' +
        '/TalFlowExpress/s/order-confirmation' +
        '?session_id={CHECKOUT_SESSION_ID}' +
        '&oid=' +
        orderId;
      String cancelUrl =
        'https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com' +
        '/TalFlowExpress/s/checkout';

      HttpRequest req = new HttpRequest();
      req.setEndpoint('https://api.stripe.com/v1/checkout/sessions');
      req.setMethod('POST');
      req.setHeader('Authorization', 'Bearer ' + configs[0].API_Key__c);
      req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
      req.setTimeout(15000);
      req.setBody(
        'mode=payment' +
          '&success_url=' +
          EncodingUtil.urlEncode(successUrl, 'UTF-8') +
          '&cancel_url=' +
          EncodingUtil.urlEncode(cancelUrl, 'UTF-8') +
          (String.isNotBlank(email) && email.contains('@')
            ? '&customer_email=' + EncodingUtil.urlEncode(email, 'UTF-8')
            : '') +
          '&line_items[0][price_data][currency]=usd' +
          '&line_items[0][price_data][unit_amount]=' +
          amountInCents +
          '&line_items[0][price_data][product_data][name]=' +
          EncodingUtil.urlEncode('TalFlow Express Order', 'UTF-8') +
          '&line_items[0][quantity]=1'
      );

      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() == 200) {
        Map<String, Object> session = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        String url = (String) session.get('url');
        if (String.isBlank(url)) {
          throw new AuraHandledException(
            'Stripe URL null: ' + res.getBody().left(300)
          );
        }
        return url;
      }
      throw new AuraHandledException(
        'Stripe HTTP ' + res.getStatusCode() + ': ' + res.getBody().left(300)
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 6. Confirm Order ──────────────────────────────────────
  @AuraEnabled
  public static ConfirmResult confirmOrder(String orderId, String sessionId) {
    try {
      ConfirmResult result = new ConfirmResult();
      result.success = false;

      // ── COD ───────────────────────────────────────────
      if (String.isBlank(sessionId)) {
        if (String.isBlank(orderId))
          return result;

        Order ord = [
          SELECT
            Id,
            OrderNumber,
            Total_TTC__c,
            Payment_Method__c,
            EffectiveDate,
            ShippingStreet,
            ShippingCity,
            ShippingState,
            ShippingPostalCode,
            ShippingCountry,
            ShippingCountryCode,
            Email__c,
            Phone__c
          FROM Order
          WHERE Id = :orderId
          LIMIT 1
        ];

        result.success = true;
        result.orderNumber = ord.OrderNumber;
        result.totalTTC = ord.Total_TTC__c;
        result.paymentMethod = ord.Payment_Method__c;
        result.orderDate = ord.EffectiveDate != null
          ? ord.EffectiveDate.format()
          : '';
        result.shippingStreet = ord.ShippingStreet;
        result.shippingCity = ord.ShippingCity;
        result.shippingState = ord.ShippingState;
        result.shippingZip = ord.ShippingPostalCode;
        result.shippingCountry = ord.ShippingCountry;
        result.customerEmail = ord.Email__c;
        result.customerPhone = ord.Phone__c;
        return result;
      }

      // ── Card (Stripe) ─────────────────────────────────
      API_Config__mdt config = [
        SELECT API_Key__c
        FROM API_Config__mdt
        WHERE DeveloperName = 'Stripe'
        LIMIT 1
      ];

      HttpRequest req = new HttpRequest();
      req.setEndpoint(
        'https://api.stripe.com/v1/checkout/sessions/' + sessionId
      );
      req.setMethod('GET');
      req.setHeader('Authorization', 'Bearer ' + config.API_Key__c);
      req.setTimeout(15000);

      HttpResponse res = new Http().send(req);

      if (res.getStatusCode() == 200) {
        Map<String, Object> session = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        String paymentStatus = (String) session.get('payment_status');

        if (paymentStatus == 'paid') {
          String userId = System.UserInfo.getUserId();

          if (String.isBlank(orderId)) {
            Id accountId = null;
            List<User> users = [
              SELECT ContactId
              FROM User
              WHERE Id = :userId AND ContactId != NULL
              LIMIT 1
            ];
            if (!users.isEmpty()) {
              List<Contact> contacts = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :users[0].ContactId
                LIMIT 1
              ];
              if (!contacts.isEmpty()) {
                accountId = contacts[0].AccountId;
              }
            }
            if (accountId != null) {
              List<Order> orders = [
                SELECT Id
                FROM Order
                WHERE Status = 'Activated' AND AccountId = :accountId
                ORDER BY CreatedDate DESC
                LIMIT 1
              ];
              if (!orders.isEmpty()) {
                orderId = orders[0].Id;
              }
            }
          }

          if (String.isBlank(orderId)) {
            List<Order> orders = [
              SELECT Id
              FROM Order
              WHERE Status = 'Activated'
              ORDER BY CreatedDate DESC
              LIMIT 1
            ];
            if (!orders.isEmpty())
              orderId = orders[0].Id;
          }

          if (String.isBlank(orderId))
            return result;

          // ⭐ Load Order with B2B fields needed for Invoice creation
          Order ord = [
            SELECT
              Id,
              OrderNumber,
              Total_TTC__c,
              Payment_Method__c,
              EffectiveDate,
              ShippingStreet,
              ShippingCity,
              ShippingState,
              ShippingPostalCode,
              ShippingCountry,
              ShippingCountryCode,
              Email__c,
              Phone__c,
              AccountId,
              Quote__c,
              Subtotal__c,
              Tax_Amount__c,
              Shipping_Cost__c,
              Discount__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
          ];

          ord.Status = 'Paid';
          ord.Stripe_Payment_Id__c = sessionId;
          update ord;

          // ⭐ Update or Create Invoice
          List<Invoice__c> invList = [
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Order__c = :orderId
            LIMIT 1
          ];

          if (!invList.isEmpty()) {
            // B2C : Invoice already exists, just mark as Paid
            invList[0].Status__c = 'Paid';
            update invList;
          } else if (ord.Quote__c != null) {
            // ⭐ B2B : No invoice yet (Order from Quote), create one
            try {
              Invoice__c inv = new Invoice__c();
              inv.Order__c = orderId;
              inv.Account__c = ord.AccountId;
              inv.Status__c = 'Paid';
              inv.Payment_Method__c = 'Card';
              inv.Subtotal__c = ord.Subtotal__c != null ? ord.Subtotal__c : 0;
              inv.Tax_Amount__c = ord.Tax_Amount__c != null
                ? ord.Tax_Amount__c
                : 0;
              inv.Shipping_Cost__c = ord.Shipping_Cost__c != null
                ? ord.Shipping_Cost__c
                : 0;
              inv.Discount__c = ord.Discount__c != null ? ord.Discount__c : 0;
              inv.Total_TTC__c = ord.Total_TTC__c != null
                ? ord.Total_TTC__c
                : 0;
              inv.Country_Code__c = ord.ShippingCountryCode;
              insert inv;
              System.debug(
                '✅ B2B Invoice created for paid Order ' + ord.OrderNumber
              );
            } catch (Exception e) {
              System.debug('Failed to create B2B invoice: ' + e.getMessage());
            }
          }

          List<Cart__c> carts = [
            SELECT Id
            FROM Cart__c
            WHERE User__c = :userId AND Status__c = 'Active'
            LIMIT 1
          ];
          if (!carts.isEmpty()) {
            carts[0].Status__c = 'Completed';
            update carts;
          }

          result.success = true;
          result.orderNumber = ord.OrderNumber;
          result.totalTTC = ord.Total_TTC__c;
          result.paymentMethod = ord.Payment_Method__c;
          result.orderDate = ord.EffectiveDate != null
            ? ord.EffectiveDate.format()
            : '';
          result.shippingStreet = ord.ShippingStreet;
          result.shippingCity = ord.ShippingCity;
          result.shippingState = ord.ShippingState;
          result.shippingZip = ord.ShippingPostalCode;
          result.shippingCountry = ord.ShippingCountry;
          result.customerEmail = ord.Email__c;
          result.customerPhone = ord.Phone__c;
        }
      }
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 7. Sauvegarder adresse ────────────────────────────────
  @AuraEnabled
  public static void saveUserAddress(
    String street,
    String city,
    String state,
    String postalCode,
    String country
  ) {
    try {
      String userId = System.UserInfo.getUserId();
      updateUserAddressAsync(userId, street, city, state, postalCode, country);
      List<User> users = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (!users.isEmpty() && users[0].ContactId != null) {
        Contact con = new Contact(Id = users[0].ContactId);
        con.MailingStreet = street;
        con.MailingCity = city;
        con.MailingState = state;
        con.MailingPostalCode = postalCode;
        con.MailingCountry = country;
        update con;
      }
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @future
  private static void updateUserAddressAsync(
    String userId,
    String street,
    String city,
    String state,
    String postalCode,
    String country
  ) {
    try {
      User u = new User(Id = userId);
      u.Street = street;
      u.City = city;
      u.State = state;
      u.PostalCode = postalCode;
      u.Country = country;
      update u;
    } catch (Exception e) {
      System.debug('User address update failed: ' + e.getMessage());
    }
  }

  // ── Helpers ───────────────────────────────────────────────
  private static String getCountryCode(String countryName) {
    if (String.isBlank(countryName))
      return 'TN';
    if (countryName.length() == 2)
      return countryName.toUpperCase();
    Map<String, String> countryMap = new Map<String, String>{
      'Tunisia' => 'TN',
      'France' => 'FR',
      'Germany' => 'DE',
      'Italy' => 'IT',
      'Spain' => 'ES',
      'United Kingdom' => 'GB',
      'United States' => 'US',
      'Canada' => 'CA',
      'Australia' => 'AU',
      'Morocco' => 'MA',
      'Algeria' => 'DZ',
      'Saudi Arabia' => 'SA',
      'UAE' => 'AE',
      'Turkey' => 'TR',
      'Egypt' => 'EG'
    };
    String code = countryMap.get(countryName);
    return String.isNotBlank(code) ? code : 'TN';
  }

  private static Id findAccountId(String userId) {
    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
    if (!users.isEmpty() && users[0].ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null) {
        return contacts[0].AccountId;
      }
    }
    List<Account> accts = [
      SELECT Id
      FROM Account
      WHERE Name = 'TalFlow Customers'
      LIMIT 1
    ];
    return accts.isEmpty() ? null : accts[0].Id;
  }

  private static Id getOrCreateAccountId(String userId, Id existingId) {
    if (existingId != null)
      return existingId;
    Account a = new Account(Name = 'TalFlow Customers');
    insert a;
    return a.Id;
  }

  private static Map<Id, Id> resolvePricebookEntries(
    List<Cart_Item__c> cartItems,
    Id stdPB
  ) {
    Set<Id> productIds = new Set<Id>();
    for (Cart_Item__c ci : cartItems) {
      productIds.add(Id.valueOf(ci.Product_Id_c__c));
    }

    Map<Id, Id> productToPBE = new Map<Id, Id>();
    List<PricebookEntry> existingPBEs = [
      SELECT Id, Product2Id, IsActive
      FROM PricebookEntry
      WHERE Product2Id IN :productIds AND Pricebook2Id = :stdPB
    ];

    List<PricebookEntry> toActivate = new List<PricebookEntry>();
    for (PricebookEntry pbe : existingPBEs) {
      productToPBE.put(pbe.Product2Id, pbe.Id);
      if (!pbe.IsActive) {
        pbe.IsActive = true;
        toActivate.add(pbe);
      }
    }
    if (!toActivate.isEmpty())
      update toActivate;

    List<PricebookEntry> newPBEs = new List<PricebookEntry>();
    for (Cart_Item__c ci : cartItems) {
      Id prodId = Id.valueOf(ci.Product_Id_c__c);
      if (!productToPBE.containsKey(prodId)) {
        newPBEs.add(
          new PricebookEntry(
            Pricebook2Id = stdPB,
            Product2Id = prodId,
            UnitPrice = ci.Unit_Price_c__c,
            IsActive = true
          )
        );
      }
    }
    if (!newPBEs.isEmpty()) {
      insert newPBEs;
      for (PricebookEntry pbe : newPBEs) {
        productToPBE.put(pbe.Product2Id, pbe.Id);
      }
    }
    return productToPBE;
  }

  // ── Wrappers ──────────────────────────────────────────────
  public class ConfirmResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String shippingStreet;
    @AuraEnabled
    public String shippingCity;
    @AuraEnabled
    public String shippingState;
    @AuraEnabled
    public String shippingZip;
    @AuraEnabled
    public String shippingCountry;
    @AuraEnabled
    public String orderDate;
    @AuraEnabled
    public String customerEmail;
    @AuraEnabled
    public String customerPhone;
  }

  public class CheckoutData {
    @AuraEnabled
    public Boolean isGuest;
    @AuraEnabled
    public String cartId;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String fullName;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String postalCode;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public List<CheckoutItem> items;
    @AuraEnabled
    public Decimal subtotal;
    @AuraEnabled
    public CkTaxService.CheckoutSummary summary;
  }

  public class CheckoutItem {
    @AuraEnabled
    public String itemId;
    @AuraEnabled
    public String productId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String image;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Integer quantity;
    @AuraEnabled
    public Decimal lineTotal;
  }

  public class PromoResult {
    @AuraEnabled
    public Boolean valid;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Decimal discountPercent;
    @AuraEnabled
    public Decimal discountAmount;
  }

  public class OrderResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String redirectUrl;
    @AuraEnabled
    public String errorMessage;
  }
}
