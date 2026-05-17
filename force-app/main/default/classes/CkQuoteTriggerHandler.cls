public without sharing class CkQuoteTriggerHandler {
  private static final String QUOTE_SENT_TEMPLATE_NAME = 'B2B_Quote_Sent_to_Customer_1777598043724';
  private static final String OWEA_DISPLAY_NAME = 'Hasnaoui Yassine';

  // ═══════════════════════════════════════════════════════════
  // ENTRY POINT
  // ═══════════════════════════════════════════════════════════

  public static void handleAfterUpdate(
    List<Quote> newQuotes,
    Map<Id, Quote> oldMap
  ) {
    Set<Id> quotesNewlySent = new Set<Id>();

    for (Quote q : newQuotes) {
      Quote oldQuote = oldMap.get(q.Id);
      if (
        oldQuote.B2B_Status__c != q.B2B_Status__c &&
        q.B2B_Status__c == 'Sent to Customer'
      ) {
        quotesNewlySent.add(q.Id);
      }
    }

    if (!quotesNewlySent.isEmpty()) {
      sendQuoteToCustomer(quotesNewlySent);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SEND QUOTE TO CUSTOMER
  // ═══════════════════════════════════════════════════════════

  private static void sendQuoteToCustomer(Set<Id> quoteIds) {
    // 1. Re-query Quotes with Account name (via Opportunity)
    List<Quote> quotes = [
      SELECT
        Id,
        Status,
        ContactId,
        Customer_Name__c,
        OpportunityId,
        Opportunity.Account.Name
      FROM Quote
      WHERE Id IN :quoteIds
    ];

    // 2. Update standard Status → 'Presented' AND populate Customer_Name__c
    List<Quote> toUpdate = new List<Quote>();
    for (Quote q : quotes) {
      Quote updateQ = new Quote(Id = q.Id);
      Boolean needsUpdate = false;

      if (q.Status != 'Presented') {
        updateQ.Status = 'Presented';
        needsUpdate = true;
      }

      // Populate Customer_Name__c from Opportunity.Account.Name
      String accountName = (q.Opportunity != null &&
        q.Opportunity.Account != null)
        ? q.Opportunity.Account.Name
        : '';
      if (q.Customer_Name__c != accountName) {
        updateQ.Customer_Name__c = accountName;
        needsUpdate = true;
      }

      if (needsUpdate) {
        toUpdate.add(updateQ);
      }
    }
    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }

    // 3. Generate PDF asynchronously
    generatePdfsAsync(quoteIds);

    // 4. Send emails using Lightning Email Template
    sendEmailsViaTemplate(quotes);
  }

  // ═══════════════════════════════════════════════════════════
  // EMAIL via Lightning Email Template
  // ═══════════════════════════════════════════════════════════

  private static void sendEmailsViaTemplate(List<Quote> quotes) {
    // Get the EmailTemplate Id from API name
    List<EmailTemplate> tpls = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = :QUOTE_SENT_TEMPLATE_NAME
      LIMIT 1
    ];
    if (tpls.isEmpty()) {
      System.debug('❌ Email template not found: ' + QUOTE_SENT_TEMPLATE_NAME);
      return;
    }
    Id templateId = tpls[0].Id;

    // Get OrgWideEmailAddress
    List<OrgWideEmailAddress> oweaList = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE DisplayName = :OWEA_DISPLAY_NAME
      LIMIT 1
    ];
    Id oweaId = oweaList.isEmpty() ? null : oweaList[0].Id;

    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    for (Quote q : quotes) {
      if (q.ContactId == null) {
        System.debug('⚠️ No contact for Quote ' + q.Id);
        continue;
      }

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setTemplateId(templateId);
      mail.setTargetObjectId(q.ContactId); // Recipient (used for {{{Recipient.X}}} merge fields)
      mail.setWhatId(q.Id); // Related record (Quote) for merge fields
      mail.setSaveAsActivity(false);
      mail.setTreatTargetObjectAsRecipient(true);

      if (oweaId != null) {
        mail.setOrgWideEmailAddressId(oweaId);
      }
      emails.add(mail);
    }

    if (!emails.isEmpty()) {
      try {
        Messaging.sendEmail(emails);
        System.debug('✅ Sent ' + emails.size() + ' email(s) via template');
      } catch (Exception e) {
        System.debug('❌ Email send failed: ' + e.getMessage());
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ASYNC PDF GENERATION
  // ═══════════════════════════════════════════════════════════

  @future(callout=true)
  private static void generatePdfsAsync(Set<Id> quoteIds) {
    for (Id qId : quoteIds) {
      try {
        CkPdfService.generateAndSaveQuotePdf(qId);
        System.debug('✅ PDF generated for Quote ' + qId);
      } catch (Exception e) {
        System.debug(
          '⚠️ PDF generation failed for ' + qId + ': ' + e.getMessage()
        );
      }
    }
  }

  // Creates a notification when Quote status changes to "Sent to Customer"
  public static void notifyOnStatusChange(
    List<Quote> newQuotes,
    Map<Id, Quote> oldMap
  ) {
    if (oldMap == null)
      return;

    // 1. Detect status changes
    Set<Id> quoteIdsToNotify = new Set<Id>();
    for (Quote q : newQuotes) {
      Quote oldQuote = oldMap.get(q.Id);
      if (
        q.B2B_Status__c == 'Sent to Customer' &&
        oldQuote.B2B_Status__c != 'Sent to Customer'
      ) {
        quoteIdsToNotify.add(q.Id);
      }
    }

    if (quoteIdsToNotify.isEmpty())
      return;

    // 2. ⭐ Re-query Quotes with ALL needed fields (including GrandTotal + Opportunity.AccountId)
    Map<Id, Quote> quotesToNotify = new Map<Id, Quote>(
      [
        SELECT
          Id,
          QuoteNumber,
          GrandTotal,
          B2B_Status__c,
          OpportunityId,
          Opportunity.AccountId
        FROM Quote
        WHERE Id IN :quoteIdsToNotify
      ]
    );

    if (quotesToNotify.isEmpty())
      return;

    // 3. Get AccountIds
    Set<Id> accountIds = new Set<Id>();
    for (Quote q : quotesToNotify.values()) {
      if (q.Opportunity != null && q.Opportunity.AccountId != null) {
        accountIds.add(q.Opportunity.AccountId);
      }
    }

    if (accountIds.isEmpty())
      return;

    // 4. Find Users for these accounts
    Map<Id, User> userByAccount = new Map<Id, User>();
    for (User u : [
      SELECT Id, AccountId
      FROM User
      WHERE AccountId IN :accountIds AND IsActive = TRUE
    ]) {
      userByAccount.put(u.AccountId, u);
    }

    // 5. Create notifications
    for (Quote q : quotesToNotify.values()) {
      if (q.Opportunity == null || q.Opportunity.AccountId == null)
        continue;

      User u = userByAccount.get(q.Opportunity.AccountId);
      if (u == null)
        continue;

      Decimal grandTotal = q.GrandTotal != null ? q.GrandTotal : 0;

      CkNotificationController.createNotification(
        u.Id,
        '📄 New Quote Available',
        'Your quote ' +
          q.QuoteNumber +
          ' has been sent. Total: $' +
          grandTotal.setScale(0).format() +
          '. Click to view details.',
        'Info',
        '/TalFlowExpress/s/my-quotes',
        'document'
      );
    }
  }

  public static void createOrderFromAcceptedQuote(
    List<Quote> newQuotes,
    Map<Id, Quote> oldMap
  ) {
    if (oldMap == null)
      return;

    // 1. Detect Quotes newly accepted
    Set<Id> acceptedQuoteIds = new Set<Id>();
    for (Quote q : newQuotes) {
      Quote oldQuote = oldMap.get(q.Id);
      if (
        q.B2B_Status__c == 'Accepted' &&
        oldQuote.B2B_Status__c != 'Accepted'
      ) {
        acceptedQuoteIds.add(q.Id);
      }
    }

    if (acceptedQuoteIds.isEmpty())
      return;

    // 2. Idempotence: skip Quotes that already have an Order
    Map<Id, Order> existingOrdersByQuote = new Map<Id, Order>();
    for (Order existing : [
      SELECT Id, Quote__c
      FROM Order
      WHERE Quote__c IN :acceptedQuoteIds
    ]) {
      existingOrdersByQuote.put(existing.Quote__c, existing);
    }

    Set<Id> quotesToProcess = new Set<Id>();
    for (Id qId : acceptedQuoteIds) {
      if (!existingOrdersByQuote.containsKey(qId)) {
        quotesToProcess.add(qId);
      } else {
        System.debug('Order already exists for Quote ' + qId + ', skipping');
      }
    }

    if (quotesToProcess.isEmpty())
      return;

    // 3. Re-query Quotes with all needed fields
    Map<Id, Quote> fullQuotes = new Map<Id, Quote>(
      [
        SELECT
          Id,
          QuoteNumber,
          GrandTotal,
          Subtotal,
          Discount,
          Tax,
          ShippingHandling,
          ExpirationDate,
          ShippingStreet,
          ShippingCity,
          ShippingCountry,
          ShippingPostalCode,
          Phone,
          Email,
          Volume_Discount__c,
          Discount_Amount__c,
          Special_Terms__c,
          OpportunityId,
          Pricebook2Id,
          Opportunity.AccountId
        FROM Quote
        WHERE Id IN :quotesToProcess
      ]
    );

    // 4. Get all QuoteLineItems
    Map<Id, List<QuoteLineItem>> linesByQuote = new Map<Id, List<QuoteLineItem>>();
    for (QuoteLineItem qli : [
      SELECT
        Id,
        QuoteId,
        Product2Id,
        PricebookEntryId,
        Quantity,
        UnitPrice,
        TotalPrice,
        Product2.Name
      FROM QuoteLineItem
      WHERE QuoteId IN :quotesToProcess
    ]) {
      if (!linesByQuote.containsKey(qli.QuoteId)) {
        linesByQuote.put(qli.QuoteId, new List<QuoteLineItem>());
      }
      linesByQuote.get(qli.QuoteId).add(qli);
    }

    // 5. ⭐ NEW : Find customer User (with Contact) for each Account
    //    The customer User must own the Order so the Flow can find Contact via OwnerId
    Set<Id> accountIds = new Set<Id>();
    for (Quote q : fullQuotes.values()) {
      if (q.Opportunity != null && q.Opportunity.AccountId != null) {
        accountIds.add(q.Opportunity.AccountId);
      }
    }

    Map<Id, Id> customerUserByAccount = new Map<Id, Id>();
    if (!accountIds.isEmpty()) {
      for (User u : [
        SELECT Id, AccountId, ContactId
        FROM User
        WHERE AccountId IN :accountIds AND IsActive = TRUE AND ContactId != NULL
        ORDER BY CreatedDate ASC
      ]) {
        if (!customerUserByAccount.containsKey(u.AccountId)) {
          customerUserByAccount.put(u.AccountId, u.Id);
        }
      }
    }

    // 6. Create Orders
    List<Order> ordersToInsert = new List<Order>();
    Map<Id, Quote> quoteByOrderTemp = new Map<Id, Quote>();

    for (Quote q : fullQuotes.values()) {
      if (q.Opportunity == null || q.Opportunity.AccountId == null) {
        System.debug(
          'Skip quote ' + q.QuoteNumber + ' — no Opportunity/AccountId'
        );
        continue;
      }

      Order o = new Order();
      o.AccountId = q.Opportunity.AccountId;
      o.OpportunityId = q.OpportunityId;
      o.Quote__c = q.Id;
      o.Status = 'Draft';
      o.EffectiveDate = Date.today();
      o.Pricebook2Id = q.Pricebook2Id;

      // ⭐ NEW : Set OwnerId to customer User (so Flow finds the Contact)
      Id customerUserId = customerUserByAccount.get(q.Opportunity.AccountId);
      if (customerUserId != null) {
        o.OwnerId = customerUserId;
      }

      // Financial fields
      Decimal subtotal = q.Subtotal != null ? q.Subtotal : 0;
      Decimal discount = q.Discount_Amount__c != null
        ? q.Discount_Amount__c
        : 0;
      Decimal tax = q.Tax != null ? q.Tax : 0;
      Decimal shipping = q.ShippingHandling != null ? q.ShippingHandling : 0;
      Decimal grandTotal = q.GrandTotal != null ? q.GrandTotal : 0;

      o.Subtotal__c = subtotal;
      o.Discount__c = discount;
      o.Tax_Amount__c = tax;
      o.Shipping_Cost__c = shipping;
      o.Total_TTC__c = grandTotal;

      // Shipping info from Quote
      o.Shipping_Address__c = q.ShippingStreet;
      o.Shipping_City__c = q.ShippingCity;
      o.Shipping_Country__c = q.ShippingCountry;
      o.Shipping_Zip__c = q.ShippingPostalCode;
      o.Phone__c = q.Phone;
      o.Email__c = q.Email;

      ordersToInsert.add(o);
      quoteByOrderTemp.put(o.Quote__c, q);
    }

    if (ordersToInsert.isEmpty())
      return;

    try {
      insert ordersToInsert;
      System.debug(
        '✅ Created ' + ordersToInsert.size() + ' orders from accepted quotes'
      );
    } catch (Exception e) {
      System.debug('❌ Failed to insert orders: ' + e.getMessage());
      return;
    }

    // 7. Create OrderItems
    List<OrderItem> itemsToInsert = new List<OrderItem>();
    for (Order o : ordersToInsert) {
      Quote q = quoteByOrderTemp.get(o.Quote__c);
      if (q == null)
        continue;

      List<QuoteLineItem> qlis = linesByQuote.get(q.Id);
      if (qlis == null || qlis.isEmpty())
        continue;

      for (QuoteLineItem qli : qlis) {
        OrderItem oi = new OrderItem();
        oi.OrderId = o.Id;
        oi.Product2Id = qli.Product2Id;
        oi.PricebookEntryId = qli.PricebookEntryId;
        oi.Quantity = qli.Quantity;
        oi.UnitPrice = qli.UnitPrice;
        if (qli.Product2 != null) {
          oi.Product_Name_Text__c = qli.Product2.Name;
        }
        itemsToInsert.add(oi);
      }
    }

    if (!itemsToInsert.isEmpty()) {
      try {
        insert itemsToInsert;
        System.debug('✅ Created ' + itemsToInsert.size() + ' order items');
      } catch (Exception e) {
        System.debug('❌ Failed to insert order items: ' + e.getMessage());
      }
    }

    // 8. Create notifications
    Set<Id> notifAccountIds = new Set<Id>();
    for (Order o : ordersToInsert) {
      notifAccountIds.add(o.AccountId);
    }

    Map<Id, User> userByAccount = new Map<Id, User>();
    for (User u : [
      SELECT Id, AccountId
      FROM User
      WHERE AccountId IN :notifAccountIds AND IsActive = TRUE
    ]) {
      userByAccount.put(u.AccountId, u);
    }

    // Re-query orders to get OrderNumber
    Map<Id, Order> ordersWithNumber = new Map<Id, Order>(
      [
        SELECT Id, OrderNumber, AccountId, Quote__c, Total_TTC__c
        FROM Order
        WHERE Id IN :ordersToInsert
      ]
    );

    for (Order o : ordersWithNumber.values()) {
      User u = userByAccount.get(o.AccountId);
      if (u == null)
        continue;

      Quote q = quoteByOrderTemp.get(o.Quote__c);
      String quoteNum = q != null ? q.QuoteNumber : 'N/A';

      Decimal amt = o.Total_TTC__c != null ? o.Total_TTC__c : 0;

      CkNotificationController.createNotification(
        u.Id,
        '🎉 Order Created',
        'Order ' +
          o.OrderNumber +
          ' ($' +
          amt.setScale(0).format() +
          ') has been created from accepted quote Q-' +
          quoteNum +
          '. Please complete the payment.',
        'Success',
        '/TalFlowExpress/s/my-orders-b2b',
        'shopping-cart'
      );
    }

    // 🎯 Notify internal team about auto-created Order
    Set<Id> adminAndSalesManager = CkInternalNotificationService.getAdminUserIds();
    adminAndSalesManager.addAll(
      CkInternalNotificationService.getUsersByRole('Sales_Manager')
    );

    for (Order o : ordersWithNumber.values()) {
      Quote q = quoteByOrderTemp.get(o.Quote__c);
      String quoteNum = q != null ? q.QuoteNumber : 'N/A';
      Decimal amt = o.Total_TTC__c != null ? o.Total_TTC__c : 0;

      CkInternalNotificationService.send(
        CkInternalNotificationService.TYPE_ORDER_ACTIVITY,
        '🛒 New B2B Order',
        'Order ' +
          o.OrderNumber +
          ' ($' +
          amt.setScale(0).format() +
          ') auto-created from Quote Q-' +
          quoteNum +
          '.',
        adminAndSalesManager,
        o.Id
      );
    }
  }

  /**
   * @description Notify internal team when a Quote enters a key status.
   * Called from QuoteTrigger after update.
   */
  public static void notifyInternalTeam(
    List<Quote> newQuotes,
    Map<Id, Quote> oldMap
  ) {
    if (oldMap == null)
      return;

    // Re-query for full data (GrandTotal not in Trigger.new)
    Set<Id> changedIds = new Set<Id>();
    for (Quote q : newQuotes) {
      Quote oldQ = oldMap.get(q.Id);
      if (q.B2B_Status__c != oldQ.B2B_Status__c) {
        changedIds.add(q.Id);
      }
    }
    if (changedIds.isEmpty())
      return;

    Map<Id, Quote> fullQuotes = new Map<Id, Quote>(
      [
        SELECT
          Id,
          QuoteNumber,
          B2B_Status__c,
          GrandTotal,
          Opportunity.Account.Name
        // Is_Urgent__c
        FROM Quote
        WHERE Id IN :changedIds
      ]
    );

    Set<Id> salesTeam = CkInternalNotificationService.getSalesTeamUserIds();

    for (Quote q : fullQuotes.values()) {
      String accountName = q.Opportunity?.Account?.Name != null
        ? q.Opportunity.Account.Name
        : 'Customer';
      String amount = q.GrandTotal != null
        ? '$' + q.GrandTotal.setScale(0).format()
        : '';

      // 🎯 Quote requested by customer (Pending Approval)
      // if (q.B2B_Status__c == 'Pending Approval') {
      //   String type = (q.Is_Urgent__c == true)
      //     ? CkInternalNotificationService.TYPE_URGENT_QUOTE
      //     : CkInternalNotificationService.TYPE_QUOTE_ACTIVITY;

      //   String prefix = (q.Is_Urgent__c == true) ? '🚨 URGENT — ' : '📝 ';

      //   CkInternalNotificationService.send(
      //     type,
      //     prefix + 'New Quote Request',
      //     accountName +
      //       ' requested quote ' +
      //       q.QuoteNumber +
      //       ' for ' +
      //       amount +
      //       '. Please review.',
      //     salesTeam,
      //     q.Id
      //   );
      // }

      // 🎯 Quote requested by customer (Draft)
      // if (q.B2B_Status__c == 'Draft') {
      //   CkInternalNotificationService.send(
      //     CkInternalNotificationService.TYPE_QUOTE_ACTIVITY,
      //     '📝 New Quote Request',
      //     accountName +
      //       ' requested quote ' +
      //       q.QuoteNumber +
      //       ' for ' +
      //       amount +
      //       '. Please review.',
      //     salesTeam,
      //     q.Id
      //   );
      // }
      // 🎯 Quote accepted by customer
      // else
      if (q.B2B_Status__c == 'Accepted') {
        CkInternalNotificationService.send(
          CkInternalNotificationService.TYPE_QUOTE_ACTIVITY,
          '🎉 Quote Accepted',
          accountName +
            ' accepted quote ' +
            q.QuoteNumber +
            ' (' +
            amount +
            '). Order auto-created.',
          salesTeam,
          q.Id
        );
      }
      // 🎯 Quote refused by customer
      else if (q.B2B_Status__c == 'Refused' || q.B2B_Status__c == 'Rejected') {
        CkInternalNotificationService.send(
          CkInternalNotificationService.TYPE_QUOTE_ACTIVITY,
          '❌ Quote Refused',
          accountName +
            ' refused quote ' +
            q.QuoteNumber +
            '. Consider follow-up.',
          CkInternalNotificationService.getUsersByRole('Commercial_Agent'),
          q.Id
        );
      }
    }
  }
  /**
   * @description Notify internal team when a customer creates a new Quote (Draft).
   * Triggered on after insert.
   */
  public static void notifyInternalOnNewQuote(List<Quote> newQuotes) {
    Set<Id> quoteIds = new Set<Id>();
    for (Quote q : newQuotes) {
      if (q.B2B_Status__c == 'Draft') {
        quoteIds.add(q.Id);
      }
    }

    if (quoteIds.isEmpty())
      return;

    // Re-query with all needed fields
    List<Quote> fullQuotes = [
      SELECT
        Id,
        QuoteNumber,
        GrandTotal,
        Is_Urgent__c,
        Urgency_Reason__c,
        Opportunity.Account.Name,
        CreatedBy.Name,
        CreatedBy.UserType
      FROM Quote
      WHERE Id IN :quoteIds
    ];

    Set<Id> salesTeam = CkInternalNotificationService.getSalesTeamUserIds();
    if (salesTeam.isEmpty()) {
      System.debug('No sales team users found');
      return;
    }

    for (Quote q : fullQuotes) {
      // Only notify for customer-created quotes (skip internal admin)
      if (
        q.CreatedBy.UserType != 'PowerCustomerSuccess' &&
        q.CreatedBy.UserType != 'CspLitePortal' &&
        q.CreatedBy.UserType != 'CustomerSuccess'
      ) {
        System.debug('Skip Q-' + q.QuoteNumber + ' — not customer-created');
        continue;
      }

      String accountName = q.Opportunity?.Account?.Name != null
        ? q.Opportunity.Account.Name
        : 'Customer';
      String amount = q.GrandTotal != null
        ? '$' + q.GrandTotal.setScale(0).format()
        : '';

      if (q.Is_Urgent__c == true) {
        // 🚨 URGENT — Special notification + immediate email
        String reasonText = String.isNotBlank(q.Urgency_Reason__c)
          ? ' Reason: ' + q.Urgency_Reason__c
          : '';

        CkInternalNotificationService.send(
          CkInternalNotificationService.TYPE_URGENT_QUOTE,
          '🚨 URGENT Quote Request — ' + q.QuoteNumber,
          accountName +
            ' submitted an URGENT quote (' +
            amount +
            '). 24h SLA active.' +
            reasonText,
          salesTeam,
          q.Id
        );

        // Send immediate email alert
        sendUrgentQuoteEmail(q, accountName, amount);
      } else {
        // 📝 Normal Quote
        CkInternalNotificationService.send(
          CkInternalNotificationService.TYPE_QUOTE_ACTIVITY,
          '📝 New Quote Request',
          accountName +
            ' requested a new quote ' +
            q.QuoteNumber +
            ' (' +
            amount +
            '). Please review within 72h.',
          salesTeam,
          q.Id
        );
      }
    }
  }

  /**
   * @description Send immediate email alert to Sales Manager for URGENT quotes.
   */
  private static void sendUrgentQuoteEmail(
    Quote q,
    String accountName,
    String amount
  ) {
    try {
      // Get Sales Manager emails
      List<User> recipients = [
        SELECT Email
        FROM User
        WHERE
          UserRole.DeveloperName = 'Sales_Manager'
          AND IsActive = TRUE
          AND Email != NULL
      ];

      if (recipients.isEmpty()) {
        System.debug('No Sales Manager users found for urgent email');
        return;
      }

      List<String> toAddresses = new List<String>();
      for (User u : recipients)
        toAddresses.add(u.Email);

      String reasonHtml = String.isNotBlank(q.Urgency_Reason__c)
        ? '<table width="100%" cellpadding="0" cellspacing="0" style="background:#FFF8F5;border:1.5px solid #FFE4D4;border-radius:10px;margin-bottom:20px;">' +
          '<tr><td style="padding:16px 20px;">' +
          '<p style="color:#0A1628;margin:0 0 6px;font-size:13px;font-weight:bold;">📋 Reason for Urgency</p>' +
          '<p style="color:#495057;margin:0;font-size:13px;line-height:1.5;">' +
          q.Urgency_Reason__c +
          '</p>' +
          '</td></tr></table>'
        : '';

      String htmlBody =
        '<html><body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:30px 0;">' +
        '<tr><td align="center">' +
        '<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 16px rgba(0,0,0,0.1);">' +
        // Header
        '<tr><td style="background:#0A1628;padding:24px;text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;letter-spacing:1px;">TalFlow Express</h1>' +
        '<p style="color:#fff;margin:8px 0 0;font-size:13px;">B2B Sales Management</p>' +
        '</td></tr>' +
        // Red banner
        '<tr><td style="background:#E24B4A;padding:18px;text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:18px;font-weight:bold;">🚨 URGENT Quote Request</p>' +
        '<p style="color:#fff;margin:6px 0 0;font-size:12px;opacity:0.9;">24-hour SLA active — Immediate response required</p>' +
        '</td></tr>' +
        // Body
        '<tr><td style="padding:32px 28px;">' +
        '<p style="color:#0A1628;font-size:15px;margin:0 0 16px;">Hi Sales Manager,</p>' +
        '<p style="color:#495057;font-size:14px;line-height:1.6;margin:0 0 20px;">' +
        'An <strong>urgent quote request</strong> has been submitted and requires your immediate attention. ' +
        'Please review and respond within <strong>24 hours</strong>.</p>' +
        // Quote details
        '<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F8FF;border:1.5px solid #B8D4F0;border-radius:10px;margin-bottom:20px;">' +
        '<tr><td style="padding:16px 20px;">' +
        '<p style="color:#0A1628;margin:0 0 12px;font-size:13px;font-weight:bold;">📋 Quote Details</p>' +
        '<table width="100%" cellpadding="4" cellspacing="0">' +
        '<tr><td style="color:#495057;font-size:13px;width:120px;"><strong>Quote Number:</strong></td><td style="color:#0A1628;font-size:13px;">' +
        q.QuoteNumber +
        '</td></tr>' +
        '<tr><td style="color:#495057;font-size:13px;"><strong>Customer:</strong></td><td style="color:#0A1628;font-size:13px;">' +
        accountName +
        '</td></tr>' +
        '<tr><td style="color:#495057;font-size:13px;"><strong>Amount:</strong></td><td style="color:#0A1628;font-size:13px;font-weight:bold;">' +
        amount +
        '</td></tr>' +
        '<tr><td style="color:#495057;font-size:13px;"><strong>Submitted:</strong></td><td style="color:#0A1628;font-size:13px;">' +
        System.now().format('yyyy-MM-dd HH:mm') +
        '</td></tr>' +
        '<tr><td style="color:#495057;font-size:13px;"><strong>SLA Deadline:</strong></td><td style="color:#E24B4A;font-size:13px;font-weight:bold;">' +
        System.now().addHours(24).format('yyyy-MM-dd HH:mm') +
        '</td></tr>' +
        '</table>' +
        '</td></tr></table>' +
        // Reason
        reasonHtml +
        // CTA
        '<table width="100%" cellpadding="0" cellspacing="0" style="margin-top:24px;">' +
        '<tr><td align="center">' +
        '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.salesforce.com/' +
        q.Id +
        '" ' +
        'style="display:inline-block;background:#E24B4A;color:#fff;padding:14px 36px;border-radius:10px;text-decoration:none;font-size:13px;font-weight:bold;">' +
        'View Quote in Salesforce →</a>' +
        '</td></tr></table>' +
        '</td></tr>' +
        // Footer
        '<tr><td style="background:#0A1628;padding:20px 28px;text-align:center;">' +
        '<p style="color:#FF6B1A;font-size:12px;font-weight:bold;margin:0 0 4px;">TalFlow Express</p>' +
        '<p style="color:#868E96;font-size:11px;margin:0;">Automated Urgent Quote Notification</p>' +
        '</td></tr>' +
        '</table></td></tr></table>' +
        '</body></html>';

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

      // Use Org-Wide Email Address if available
      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        LIMIT 1
      ];
      if (!owea.isEmpty()) {
        mail.setOrgWideEmailAddressId(owea[0].Id);
      }

      mail.setToAddresses(toAddresses);
      mail.setSubject(
        '🚨 URGENT Quote ' + q.QuoteNumber + ' — 24h SLA — ' + accountName
      );
      mail.setHtmlBody(htmlBody);
      mail.setSaveAsActivity(false);

      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
      System.debug(
        '✅ Urgent quote email sent to ' +
          toAddresses.size() +
          ' Sales Manager(s)'
      );
    } catch (Exception e) {
      System.debug('Failed to send urgent quote email: ' + e.getMessage());
    }
  }
}
