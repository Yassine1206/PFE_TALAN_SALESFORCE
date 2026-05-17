public without sharing class CkOrderController {
  // ── 1. Liste des commandes ────────────────────────────────
  @AuraEnabled(cacheable=true)
  public static List<OrderSummary> getMyOrders() {
    try {
      String userId = System.UserInfo.getUserId();

      List<User> users = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (users.isEmpty() || users[0].ContactId == null) {
        return new List<OrderSummary>();
      }

      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        LIMIT 1
      ];
      if (contacts.isEmpty() || contacts[0].AccountId == null) {
        return new List<OrderSummary>();
      }

      List<Order> orders = [
        SELECT
          Id,
          OrderNumber,
          EffectiveDate,
          Status,
          Total_TTC__c,
          Payment_Method__c,
          ShippingCity,
          ShippingCountry, // ← standards
          (SELECT Id FROM OrderItems)
        FROM Order
        WHERE AccountId = :contacts[0].AccountId
        ORDER BY EffectiveDate DESC
      ];

      List<OrderSummary> results = new List<OrderSummary>();
      for (Order o : orders) {
        OrderSummary s = new OrderSummary();
        s.orderId = o.Id;
        s.orderNumber = o.OrderNumber;
        s.orderDate = o.EffectiveDate != null ? o.EffectiveDate.format() : '';
        s.status = o.Status;
        s.totalTTC = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
        s.paymentMethod = o.Payment_Method__c;
        s.itemCount = o.OrderItems != null ? o.OrderItems.size() : 0;
        s.shippingCity = o.ShippingCity;
        s.shippingCountry = o.ShippingCountry;
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
        SELECT
          Id,
          OrderNumber,
          EffectiveDate,
          Status,
          Subtotal__c,
          Tax_Amount__c,
          Shipping_Cost__c,
          Discount__c,
          Total_TTC__c,
          Payment_Method__c,
          Shipping_Address__c,
          Shipping_City__c,
          Shipping_Country__c,
          Shipping_Zip__c,
          Phone__c,
          Email__c,
          Promo_Code__c,
          (
            SELECT
              Id,
              Product2Id,
              Product_Name_Text__c,
              Product_Image__c,
              Quantity,
              UnitPrice,
              TotalPrice
            FROM OrderItems
          )
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      OrderDetail d = new OrderDetail();
      d.orderId = o.Id;
      d.orderNumber = o.OrderNumber;
      d.orderDate = o.EffectiveDate != null ? o.EffectiveDate.format() : '';
      d.status = o.Status;
      d.subtotal = o.Subtotal__c != null ? o.Subtotal__c : 0;
      d.taxAmount = o.Tax_Amount__c != null ? o.Tax_Amount__c : 0;
      d.shippingCost = o.Shipping_Cost__c != null ? o.Shipping_Cost__c : 0;
      d.discount = o.Discount__c != null ? o.Discount__c : 0;
      d.totalTTC = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
      d.paymentMethod = o.Payment_Method__c;
      d.shippingAddress = o.Shipping_Address__c;
      d.shippingCity = o.Shipping_City__c;
      d.shippingCountry = o.Shipping_Country__c;
      d.shippingZip = o.Shipping_Zip__c;
      d.phone = o.Phone__c;
      d.email = o.Email__c;
      d.promoCode = o.Promo_Code__c;

      // Invoice
      List<Invoice__c> invoices = [
        SELECT Id, Status__c, Tax_Rate__c
        FROM Invoice__c
        WHERE Order__c = :orderId
        LIMIT 1
      ];
      if (!invoices.isEmpty()) {
        d.invoiceStatus = invoices[0].Status__c;
        d.taxRate = invoices[0].Tax_Rate__c != null
          ? invoices[0].Tax_Rate__c
          : 0;
      }

      // Items
      d.items = new List<OrderItemDetail>();
      for (OrderItem oi : o.OrderItems) {
        OrderItemDetail item = new OrderItemDetail();
        item.itemId = oi.Id;
        item.productId = oi.Product2Id;
        item.name = oi.Product_Name_Text__c;
        item.image = oi.Product_Image__c;
        item.quantity = Integer.valueOf(oi.Quantity);
        item.unitPrice = oi.UnitPrice;
        item.totalPrice = oi.TotalPrice;
        d.items.add(item);
      }

      return d;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ═══════════════════════════════════════════════════════════
  // B2B EXTENSIONS — Stats + filters for the dedicated B2B page
  // ═══════════════════════════════════════════════════════════

  /**
   * @description Returns orders for B2B view with status badges + items count.
   */
  @AuraEnabled(cacheable=true)
  public static List<OrderSummaryB2B> getMyOrdersB2B() {
    try {
      String userId = System.UserInfo.getUserId();

      List<User> users = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (users.isEmpty() || users[0].ContactId == null) {
        return new List<OrderSummaryB2B>();
      }

      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        LIMIT 1
      ];
      if (contacts.isEmpty() || contacts[0].AccountId == null) {
        return new List<OrderSummaryB2B>();
      }

      List<Order> orders = [
        SELECT
          Id,
          OrderNumber,
          EffectiveDate,
          Status,
          Total_TTC__c,
          Payment_Method__c,
          CreatedDate,
          (SELECT Id FROM OrderItems)
        FROM Order
        WHERE AccountId = :contacts[0].AccountId
        ORDER BY EffectiveDate DESC NULLS LAST, CreatedDate DESC
      ];

      List<OrderSummaryB2B> results = new List<OrderSummaryB2B>();
      for (Order o : orders) {
        OrderSummaryB2B s = new OrderSummaryB2B();
        s.orderId = o.Id;
        s.orderNumber = o.OrderNumber;
        s.orderDate = o.EffectiveDate != null ? o.EffectiveDate.format() : '';
        s.status = o.Status;
        s.totalTTC = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
        s.paymentMethod = o.Payment_Method__c;
        s.itemCount = o.OrderItems != null ? o.OrderItems.size() : 0;
        s.statusClass = getStatusClassB2B(o.Status);
        s.createdDate = o.CreatedDate;
        results.add(s);
      }
      return results;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
  /**
   * @description Returns aggregate stats for the B2B Orders dashboard cards.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getMyOrdersB2BStats() {
    Map<String, Object> stats = new Map<String, Object>{
      'totalOrders' => 0,
      'totalSpent' => 0,
      'pendingCount' => 0,
      'deliveredCount' => 0
    };

    try {
      String userId = System.UserInfo.getUserId();

      List<User> users = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (users.isEmpty() || users[0].ContactId == null)
        return stats;

      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        LIMIT 1
      ];
      if (contacts.isEmpty() || contacts[0].AccountId == null)
        return stats;

      Id accountId = contacts[0].AccountId;

      Integer total = [SELECT COUNT() FROM Order WHERE AccountId = :accountId];
      stats.put('totalOrders', total);

      AggregateResult[] sumResult = [
        SELECT SUM(Total_TTC__c) total
        FROM Order
        WHERE
          AccountId = :accountId
          AND Status IN ('Activated', 'Shipped', 'Delivered')
      ];
      Decimal totalSpent = !sumResult.isEmpty() &&
        sumResult[0].get('total') != null
        ? (Decimal) sumResult[0].get('total')
        : 0;
      stats.put('totalSpent', totalSpent);

      Integer pending = [
        SELECT COUNT()
        FROM Order
        WHERE AccountId = :accountId AND Status IN ('Draft', 'Activated')
      ];
      stats.put('pendingCount', pending);

      Integer delivered = [
        SELECT COUNT()
        FROM Order
        WHERE AccountId = :accountId AND Status = 'Delivered'
      ];
      stats.put('deliveredCount', delivered);

      return stats;
    } catch (Exception e) {
      return stats;
    }
  }

  private static String getStatusClassB2B(String status) {
    if (status == 'Delivered')
      return 'status-delivered';
    if (status == 'Shipped')
      return 'status-shipped';
    if (status == 'Activated')
      return 'status-activated';
    if (status == 'Draft')
      return 'status-draft';
    if (status == 'Cancelled')
      return 'status-cancelled';
    return 'status-default';
  }

  // ═══════════════════════════════════════════════════════════
  // B2B PAYMENT — Pay an existing Draft order from /s/my-orders-b2b
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled
  public static PaymentResult payB2BOrder(
    String orderId,
    String paymentMethod
  ) {
    try {
      if (String.isBlank(orderId)) {
        throw new AuraHandledException('Order ID required.');
      }

      Order ord = [
        SELECT Id, OrderNumber, Status, Total_TTC__c, AccountId, Email__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      if (ord.Status != 'Draft') {
        throw new AuraHandledException(
          'This order cannot be paid. Status: ' + ord.Status
        );
      }

      Decimal totalTTC = ord.Total_TTC__c != null ? ord.Total_TTC__c : 0;
      if (totalTTC <= 0) {
        throw new AuraHandledException('Invalid order amount.');
      }

      PaymentResult result = new PaymentResult();
      result.success = false;
      result.orderId = ord.Id;
      result.orderNumber = ord.OrderNumber;
      result.totalTTC = totalTTC;

      // ── COD : Direct update (DML allowed, no callout) ────────
      if (paymentMethod == 'COD') {
        ord.Status = 'Pending';
        ord.Payment_Method__c = 'COD';
        update ord;

        createInvoiceIfMissing(ord.Id, paymentMethod);
        createPaymentNotification(ord, 'COD');
        // 🎯 Notify Admin + Sales Manager
        Set<Id> internalRecipients = CkInternalNotificationService.getAdminUserIds();
        internalRecipients.addAll(
          CkInternalNotificationService.getUsersByRole('Sales_Manager')
        );

        String paidStatus = (paymentMethod == 'COD')
          ? 'is awaiting delivery payment'
          : 'has been paid via Stripe';

        CkInternalNotificationService.send(
          CkInternalNotificationService.TYPE_ORDER_ACTIVITY,
          '💰 Order Payment Update',
          'Order ' +
            ord.OrderNumber +
            ' ($' +
            totalTTC.setScale(0).format() +
            ') ' +
            paidStatus +
            '.',
          internalRecipients,
          ord.Id
        );
        result.success = true;
        result.paymentMethod = 'COD';
        result.redirectUrl =
          '/TalFlowExpress/s/order-confirmation?orderId=' +
          ord.Id +
          '&method=COD';
        return result;
      }

      // ── Card : Stripe callout FIRST, then DML ────────────────
      if (paymentMethod == 'Card') {
        // ⭐ CRITICAL: Callout BEFORE any DML
        String stripeUrl = CkCheckoutController.createStripeSessionWithOrder(
          ord.Id,
          totalTTC,
          ord.Email__c
        );

        // DML AFTER callout
        ord.Payment_Method__c = 'Card';
        update ord;

        result.success = true;
        result.paymentMethod = 'Card';
        result.redirectUrl = stripeUrl;
        return result;
      }

      throw new AuraHandledException(
        'Unknown payment method: ' + paymentMethod
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException('Payment failed: ' + e.getMessage());
    }
  }

  /**
   * Creates a full Invoice for the Order if missing.
   * Copies all financial details + sets proper status based on payment method.
   */
  private static void createInvoiceIfMissing(Id orderId, String paymentMethod) {
    List<Invoice__c> existing = [
      SELECT Id
      FROM Invoice__c
      WHERE Order__c = :orderId
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      System.debug('Invoice already exists for Order ' + orderId);
      return;
    }

    try {
      Order o = [
        SELECT
          Id,
          OrderNumber,
          AccountId,
          Subtotal__c,
          Tax_Amount__c,
          Shipping_Cost__c,
          Discount__c,
          Total_TTC__c,
          Payment_Method__c,
          ShippingCountryCode
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
      ];

      String invStatus = (paymentMethod == 'Card') ? 'Paid' : 'Sent';

      Invoice__c inv = new Invoice__c();
      inv.Order__c = orderId;
      inv.Account__c = o.AccountId;
      inv.Status__c = invStatus;
      inv.Payment_Method__c = paymentMethod;
      inv.Subtotal__c = o.Subtotal__c != null ? o.Subtotal__c : 0;
      inv.Tax_Amount__c = o.Tax_Amount__c != null ? o.Tax_Amount__c : 0;
      inv.Shipping_Cost__c = o.Shipping_Cost__c != null
        ? o.Shipping_Cost__c
        : 0;
      inv.Discount__c = o.Discount__c != null ? o.Discount__c : 0;
      inv.Total_TTC__c = o.Total_TTC__c != null ? o.Total_TTC__c : 0;
      inv.Country_Code__c = o.ShippingCountryCode;
      insert inv;
      System.debug('✅ Invoice created for Order ' + o.OrderNumber);
    } catch (Exception e) {
      System.debug('❌ Failed to create invoice: ' + e.getMessage());
    }
  }

  /**
   * @description Creates a notification when payment is processed.
   */
  private static void createPaymentNotification(Order ord, String method) {
    if (ord.AccountId == null)
      return;

    List<User> users = [
      SELECT Id
      FROM User
      WHERE AccountId = :ord.AccountId AND IsActive = TRUE
      LIMIT 1
    ];
    if (users.isEmpty())
      return;

    String title;
    String message;

    if (method == 'COD') {
      title = '🚚 Order Confirmed';
      message =
        'Order ' +
        ord.OrderNumber +
        ' is confirmed. Payment will be collected on delivery.';
    } else {
      title = '💳 Payment Successful';
      message =
        'Order ' +
        ord.OrderNumber +
        ' has been paid. We will start preparing your delivery.';
    }

    CkNotificationController.createNotification(
      users[0].Id,
      title,
      message,
      'Success',
      '/TalFlowExpress/s/my-orders-b2b',
      'shopping-cart'
    );
  }

  // ── Wrappers ──────────────────────────────────────────────
  public class OrderSummary {
    @AuraEnabled
    public String orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String orderDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public Integer itemCount;
    @AuraEnabled
    public String shippingCity;
    @AuraEnabled
    public String shippingCountry;
  }

  public class OrderDetail {
    @AuraEnabled
    public String orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String orderDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal subtotal;
    @AuraEnabled
    public Decimal taxAmount;
    @AuraEnabled
    public Decimal taxRate;
    @AuraEnabled
    public Decimal shippingCost;
    @AuraEnabled
    public Decimal discount;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String shippingAddress;
    @AuraEnabled
    public String shippingCity;
    @AuraEnabled
    public String shippingCountry;
    @AuraEnabled
    public String shippingZip;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String promoCode;
    @AuraEnabled
    public String invoiceStatus;
    @AuraEnabled
    public List<OrderItemDetail> items;
  }

  public class OrderItemDetail {
    @AuraEnabled
    public String itemId;
    @AuraEnabled
    public String productId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String image;
    @AuraEnabled
    public Integer quantity;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Decimal totalPrice;
  }

  // ── Wrapper pour la vue B2B (basée sur OrderSummary + extras) ──
  public class OrderSummaryB2B {
    @AuraEnabled
    public String orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String orderDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public Integer itemCount;
    @AuraEnabled
    public String statusClass;
    @AuraEnabled
    public DateTime createdDate;
  }

  // ── Wrapper pour le paiement ──
  public class PaymentResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String redirectUrl;
  }
}
