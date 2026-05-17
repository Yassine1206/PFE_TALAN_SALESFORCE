public without sharing class CkQuoteController {
  // ── Grille de remises ────────────────────────────────────
  private static Decimal getVolumeDiscount(Decimal total) {
    if (total >= 10000)
      return 15;
    if (total >= 5000)
      return 5;
    return 0;
  }

  // ── 1. Récupérer le catalogue B2B ────────────────────────
  @AuraEnabled(cacheable=true)
  public static List<B2BProduct> getB2BProducts() {
    try {
      List<Product2> products = [
        SELECT
          Id,
          Name,
          Description,
          Family,
          B2B_Price__c,
          Image_URL__c,
          Stock_Quantity__c
        FROM Product2
        WHERE IsActive = TRUE AND B2B_Price__c > 0
        ORDER BY Name
      ];

      List<B2BProduct> result = new List<B2BProduct>();
      for (Product2 p : products) {
        B2BProduct bp = new B2BProduct();
        bp.productId = p.Id;
        bp.name = p.Name;
        bp.description = p.Description;
        bp.family = p.Family;
        bp.b2bPrice = p.B2B_Price__c;
        bp.imageUrl = p.Image_URL__c;
        bp.stock = p.Stock_Quantity__c != null
          ? Integer.valueOf(p.Stock_Quantity__c)
          : 0;
        bp.quantity = 0;
        result.add(bp);
      }
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 2. Soumettre une demande de devis ────────────────────
  @AuraEnabled
  public static QuoteResult submitQuoteRequest(
    String itemsJson,
    String shippingAddress,
    String shippingCity,
    String shippingCountry,
    String shippingZip,
    String requestedDeliveryDate,
    String comments,
    Boolean isUrgent,
    String urgencyReason
  ) {
    try {
      String userId = UserInfo.getUserId();

      User u = [
        SELECT
          Id,
          ContactId,
          Contact.AccountId,
          Contact.FirstName,
          Contact.LastName,
          Contact.Email
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null || u.Contact.AccountId == null) {
        throw new AuraHandledException(
          'Your account is not properly set up for B2B.'
        );
      }

      // Parser les items
      List<QuoteItem> items = (List<QuoteItem>) JSON.deserialize(
        itemsJson,
        List<QuoteItem>.class
      );

      if (items.isEmpty()) {
        throw new AuraHandledException('Please select at least one product.');
      }

      // Calculer le total brut
      Decimal totalBrut = 0;
      Integer totalQty = 0;
      for (QuoteItem item : items) {
        if (item.quantity <= 0)
          continue;
        totalBrut += item.unitPrice * item.quantity;
        totalQty += item.quantity;
      }

      // Vérifier minimums
      if (totalBrut < 1000) {
        throw new AuraHandledException(
          'Minimum order amount is 1,000 TND. ' +
            'Current total: ' +
            totalBrut +
            ' TND.'
        );
      }
      if (totalQty < 5) {
        throw new AuraHandledException(
          'Minimum 5 items required. ' +
            'Current total: ' +
            totalQty +
            ' items.'
        );
      }

      // Calculer remise volume
      Decimal discountPercent = getVolumeDiscount(totalBrut);
      Decimal discountAmount = totalBrut * (discountPercent / 100);
      Decimal totalAfterDiscount = totalBrut - discountAmount;

      // TVA 19%
      Decimal taxRate = 19;
      Decimal taxAmount = totalAfterDiscount * (taxRate / 100);
      Decimal totalTTC = totalAfterDiscount + taxAmount;

      // 1. Créer Opportunity
      Opportunity opp = new Opportunity();
      opp.Name = u.Contact.LastName + ' — B2B Quote';
      opp.AccountId = u.Contact.AccountId;
      opp.StageName = 'Quoting';
      opp.CloseDate = Date.today().addDays(30);
      opp.Amount = totalTTC;
      opp.LeadSource = 'Web';
      opp.Description =
        'Quote Request from B2B Portal\n' +
        'Items: ' +
        totalQty +
        '\n' +
        'Volume Discount: ' +
        discountPercent +
        '%\n' +
        (String.isNotBlank(comments) ? 'Comments: ' + comments : '');
      insert opp;

      // 2. Récupérer PricebookEntry standard
      Id stdPricebookId = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE
        LIMIT 1
      ]
      .Id;

      // 3. Créer Quote
      Quote q = new Quote();
      q.Name = 'Q-' + u.Contact.LastName + '-' + Date.today().format();
      q.OpportunityId = opp.Id;
      q.Pricebook2Id = stdPricebookId;
      q.Status = 'Draft';
      q.B2B_Status__c = 'Draft';
      q.ExpirationDate = Date.today().addDays(30);
      q.ShippingStreet = shippingAddress;
      q.ShippingCity = shippingCity;
      q.ShippingCountry = shippingCountry;
      q.ShippingPostalCode = shippingZip;
      q.ContactId = u.ContactId;
      q.Volume_Discount__c = discountPercent;
      q.Discount_Amount__c = discountAmount;
      q.Tax = taxAmount;
      q.Description = comments;
      q.Special_Terms__c =
        'Payment Terms: Net 30\n' +
        'Delivery: ' +
        requestedDeliveryDate +
        '\n' +
        'Volume Discount: ' +
        discountPercent +
        '%';

      if (String.isNotBlank(requestedDeliveryDate)) {
        q.Requested_Delivery_Date__c = Date.valueOf(requestedDeliveryDate);
      }
      q.Is_Urgent__c = (isUrgent != null && isUrgent);
      if (q.Is_Urgent__c && String.isNotBlank(urgencyReason)) {
        q.Urgency_Reason__c = urgencyReason;
      }
      insert q;

      // 4. Créer QuoteLineItems
      List<QuoteLineItem> lineItems = new List<QuoteLineItem>();
      for (QuoteItem item : items) {
        if (item.quantity <= 0)
          continue;

        // Récupérer PricebookEntry
        List<PricebookEntry> pbes = [
          SELECT Id
          FROM PricebookEntry
          WHERE
            Product2Id = :item.productId
            AND Pricebook2Id = :stdPricebookId
            AND IsActive = TRUE
          LIMIT 1
        ];

        if (pbes.isEmpty()) {
          // Créer PricebookEntry si n'existe pas
          PricebookEntry pbe = new PricebookEntry();
          pbe.Pricebook2Id = stdPricebookId;
          pbe.Product2Id = item.productId;
          pbe.UnitPrice = item.unitPrice;
          pbe.IsActive = true;
          insert pbe;
          pbes.add(pbe);
        }

        QuoteLineItem qli = new QuoteLineItem();
        qli.QuoteId = q.Id;
        qli.PricebookEntryId = pbes[0].Id;
        qli.Quantity = item.quantity;
        qli.UnitPrice = item.unitPrice;
        qli.Description = item.productName;
        lineItems.add(qli);
      }
      if (!lineItems.isEmpty())
        insert lineItems;

      // 5. Email au client
      sendQuoteConfirmationEmail(
        u.Contact.Email,
        u.Contact.FirstName,
        q.Name,
        totalBrut,
        discountPercent,
        discountAmount,
        taxAmount,
        totalTTC,
        totalQty
      );

      // 6. Email admin
      sendAdminQuoteNotification(
        q.Name,
        u.Contact.FirstName + ' ' + u.Contact.LastName,
        u.Contact.Email,
        totalTTC,
        totalQty,
        discountPercent,
        comments
      );

      // Retourner le résultat
      QuoteResult result = new QuoteResult();
      result.quoteId = q.Id;
      result.quoteName = q.Name;
      result.subtotal = totalBrut;
      result.discountPercent = discountPercent;
      result.discountAmount = discountAmount;
      result.taxAmount = taxAmount;
      result.totalTTC = totalTTC;
      result.totalItems = totalQty;
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 3. Liste des quotes du client ────────────────────────
  @AuraEnabled(cacheable=true)
  public static List<QuoteSummary> getMyQuotes() {
    try {
      String userId = UserInfo.getUserId();
      User u = [
        SELECT ContactId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (u.ContactId == null)
        return new List<QuoteSummary>();

      List<Quote> quotes = [
        SELECT
          Id,
          Name,
          QuoteNumber,
          Status,
          B2B_Status__c,
          GrandTotal,
          Volume_Discount__c,
          Discount_Amount__c,
          ExpirationDate,
          CreatedDate,
          Opportunity.Name,
          (SELECT Id FROM QuoteLineItems)
        FROM Quote
        WHERE ContactId = :u.ContactId
        ORDER BY CreatedDate DESC
      ];

      List<QuoteSummary> result = new List<QuoteSummary>();
      for (Quote q : quotes) {
        QuoteSummary qs = new QuoteSummary();
        qs.quoteId = q.Id;
        qs.quoteName = q.Name;
        qs.quoteNumber = q.QuoteNumber;
        qs.status = q.B2B_Status__c;
        qs.grandTotal = q.GrandTotal;
        qs.discountPercent = q.Volume_Discount__c;
        qs.expirationDate = q.ExpirationDate != null
          ? q.ExpirationDate.format()
          : '';
        qs.createdDate = q.CreatedDate != null ? q.CreatedDate.format() : '';
        qs.itemCount = q.QuoteLineItems != null ? q.QuoteLineItems.size() : 0;
        result.add(qs);
      }
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 4. Détail d'un quote ─────────────────────────────────
  @AuraEnabled(cacheable=true)
  public static QuoteDetail getQuoteDetail(String quoteId) {
    try {
      Quote q = [
        SELECT
          Id,
          Name,
          QuoteNumber,
          Status,
          B2B_Status__c,
          Subtotal,
          TotalPrice,
          GrandTotal,
          Tax,
          Volume_Discount__c,
          Discount_Amount__c,
          ExpirationDate,
          CreatedDate,
          Description,
          Special_Terms__c,
          Requested_Delivery_Date__c,
          ShippingStreet,
          ShippingCity,
          ShippingCountry,
          ShippingPostalCode,
          ContactId,
          Contact.FirstName,
          Contact.LastName,
          Contact.Email,
          Opportunity.Name,
          Opportunity.StageName,
          (
            SELECT
              Id,
              Product2.Name,
              Quantity,
              UnitPrice,
              TotalPrice,
              Product2.Image_URL__c,
              Description
            FROM QuoteLineItems
          )
        FROM Quote
        WHERE Id = :quoteId
        LIMIT 1
      ];

      QuoteDetail d = new QuoteDetail();
      d.quoteId = q.Id;
      d.quoteName = q.Name;
      d.quoteNumber = q.QuoteNumber;
      d.status = q.B2B_Status__c;
      d.subtotal = q.Subtotal;
      d.grandTotal = q.GrandTotal;
      d.tax = q.Tax;
      d.discountPercent = q.Volume_Discount__c;
      d.discountAmount = q.Discount_Amount__c;
      d.expirationDate = q.ExpirationDate != null
        ? q.ExpirationDate.format()
        : '';
      d.createdDate = q.CreatedDate != null ? q.CreatedDate.format() : '';
      d.specialTerms = q.Special_Terms__c;
      d.deliveryDate = q.Requested_Delivery_Date__c != null
        ? q.Requested_Delivery_Date__c.format()
        : '';
      d.shippingAddress = q.ShippingStreet;
      d.shippingCity = q.ShippingCity;
      d.shippingCountry = q.ShippingCountry;
      d.shippingZip = q.ShippingPostalCode;
      d.description = q.Description;
      d.oppName = q.Opportunity.Name;
      d.oppStage = q.Opportunity.StageName;
      d.contactName = q.Contact.FirstName + ' ' + q.Contact.LastName;
      d.contactEmail = q.Contact.Email;

      d.items = new List<QuoteItemDetail>();
      if (q.QuoteLineItems != null) {
        for (QuoteLineItem qli : q.QuoteLineItems) {
          QuoteItemDetail item = new QuoteItemDetail();
          item.itemId = qli.Id;
          item.productName = qli.Product2.Name;
          item.imageUrl = qli.Product2.Image_URL__c;
          item.quantity = Integer.valueOf(qli.Quantity);
          item.unitPrice = qli.UnitPrice;
          item.totalPrice = qli.TotalPrice;
          item.description = qli.Description;
          d.items.add(item);
        }
      }

      return d;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 5. Accepter ou Rejeter un quote ──────────────────────
  @AuraEnabled
  public static void respondToQuote(String quoteId, String response) {
    try {
      Quote q = [
        SELECT
          Id,
          B2B_Status__c,
          OpportunityId,
          ContactId,
          Contact.AccountId,
          GrandTotal,
          Name,
          Contact.FirstName,
          Contact.Email,
          Requested_Delivery_Date__c,
          Special_Terms__c
        FROM Quote
        WHERE Id = :quoteId
        LIMIT 1
      ];

      if (q.B2B_Status__c != 'Sent to Customer') {
        throw new AuraHandledException('This quote cannot be modified.');
      }

      if (response == 'Accept') {
        q.B2B_Status__c = 'Accepted';
        q.Status = 'Accepted';
        update q;

        // Mettre à jour Opportunity
        Opportunity opp = new Opportunity(Id = q.OpportunityId);
        opp.StageName = 'Closed Won';
        update opp;

        // Créer Contract
        Contract c = new Contract();
        c.AccountId = q.Contact.AccountId;
        c.Status = 'Draft';
        c.StartDate = Date.today();
        c.ContractTerm = 12;
        c.Quote__c = q.Id;
        c.Total_Amount__c = q.GrandTotal;
        c.Description =
          'Contract for Quote ' +
          q.Name +
          '\n' +
          (q.Special_Terms__c != null ? q.Special_Terms__c : '');
        insert c;

        // Email confirmation
        sendQuoteAcceptedEmail(
          q.Contact.Email,
          q.Contact.FirstName,
          q.Name,
          q.GrandTotal
        );
      } else if (response == 'Reject') {
        q.B2B_Status__c = 'Rejected';
        q.Status = 'Rejected';
        update q;

        // Mettre à jour Opportunity
        Opportunity opp = new Opportunity(Id = q.OpportunityId);
        opp.StageName = 'Closed Lost';
        update opp;
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── 6. Liste des contrats du client ──────────────────────
  @AuraEnabled(cacheable=true)
  public static List<ContractSummary> getMyContracts() {
    try {
      String userId = UserInfo.getUserId();
      User u = [
        SELECT ContactId, Contact.AccountId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];
      if (u.ContactId == null)
        return new List<ContractSummary>();

      List<Contract> contracts = [
        SELECT
          Id,
          ContractNumber,
          Status,
          StartDate,
          EndDate,
          ContractTerm,
          Total_Amount__c,
          Quote__r.Name,
          Quote__r.QuoteNumber,
          CreatedDate
        FROM Contract
        WHERE AccountId = :u.Contact.AccountId
        ORDER BY CreatedDate DESC
      ];

      List<ContractSummary> result = new List<ContractSummary>();
      for (Contract c : contracts) {
        ContractSummary cs = new ContractSummary();
        cs.contractId = c.Id;
        cs.contractNumber = c.ContractNumber;
        cs.status = c.Status;
        cs.startDate = c.StartDate != null ? c.StartDate.format() : '';
        cs.endDate = c.EndDate != null ? c.EndDate.format() : '';
        cs.totalAmount = c.Total_Amount__c;
        cs.quoteName = c.Quote__r != null ? c.Quote__r.Name : '';
        cs.quoteNumber = c.Quote__r != null ? c.Quote__r.QuoteNumber : '';
        result.add(cs);
      }
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ── Emails ───────────────────────────────────────────────
  private static void sendQuoteConfirmationEmail(
    String email,
    String firstName,
    String quoteName,
    Decimal subtotal,
    Decimal discountPercent,
    Decimal discountAmount,
    Decimal taxAmount,
    Decimal totalTTC,
    Integer totalItems
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ email });
      mail.setSubject('TalFlow Express — Quote Request Received');
      mail.setSaveAsActivity(false);

      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine'
        LIMIT 1
      ];
      if (!owea.isEmpty()) {
        mail.setOrgWideEmailAddressId(owea[0].Id);
      }

      String htmlBody =
        '<html><body style="font-family:Arial,sans-serif;' +
        'background:#f4f4f4;padding:30px 0;">' +
        '<table width="600" align="center" style="background:#fff;' +
        'border-radius:12px;overflow:hidden;">' +
        '<tr><td style="background:#0A1628;padding:28px;' +
        'text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">' +
        'TalFlow Express</h1></td></tr>' +
        '<tr><td style="background:#1971C2;padding:14px;' +
        'text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:15px;' +
        'font-weight:bold;">Quote Request Received</p></td></tr>' +
        '<tr><td style="padding:32px 36px;">' +
        '<p style="color:#0A1628;">Hi <strong>' +
        firstName +
        '</strong>,</p>' +
        '<p style="color:#495057;font-size:14px;line-height:1.7;">' +
        'We have received your quote request <strong>' +
        quoteName +
        '</strong>.</p>' +
        '<table width="100%" style="background:#F8F9FA;' +
        'border-radius:10px;margin:20px 0;">' +
        '<tr><td style="padding:16px 20px;">' +
        '<p style="color:#0A1628;font-weight:bold;' +
        'margin:0 0 12px;">Quote Summary</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        'Items: ' +
        totalItems +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        'Subtotal: $' +
        subtotal.setScale(2) +
        '</p>' +
        '<p style="color:#1D9E75;font-size:13px;margin:6px 0;">' +
        'Volume Discount (' +
        discountPercent +
        '%): -$' +
        discountAmount.setScale(2) +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        'Tax (19%): $' +
        taxAmount.setScale(2) +
        '</p>' +
        '<p style="color:#FF6B1A;font-size:16px;' +
        'font-weight:bold;margin:12px 0 0;">' +
        'Total: $' +
        totalTTC.setScale(2) +
        '</p>' +
        '</td></tr></table>' +
        '<p style="color:#495057;font-size:14px;">' +
        'Our sales team will review your request and send ' +
        'you a formal quote within 24-48 hours.</p>' +
        '<p style="color:#ADB5BD;font-size:11px;' +
        'text-align:center;margin-top:24px;">' +
        '© 2026 TalFlow Express</p>' +
        '</td></tr></table></body></html>';

      mail.setHtmlBody(htmlBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Quote email failed: ' + e.getMessage());
    }
  }

  private static void sendAdminQuoteNotification(
    String quoteName,
    String customerName,
    String customerEmail,
    Decimal totalTTC,
    Integer totalItems,
    Decimal discountPercent,
    String comments
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ 'hasnaouiyassine68@gmail.com' });
      mail.setSubject('TalFlow Express — New Quote Request: ' + quoteName);
      mail.setSaveAsActivity(false);

      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine'
        LIMIT 1
      ];
      if (!owea.isEmpty()) {
        mail.setOrgWideEmailAddressId(owea[0].Id);
      }

      String htmlBody =
        '<html><body style="font-family:Arial,sans-serif;' +
        'background:#f4f4f4;padding:30px 0;">' +
        '<table width="600" align="center" style="background:#fff;' +
        'border-radius:12px;overflow:hidden;">' +
        '<tr><td style="background:#0A1628;padding:28px;' +
        'text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">' +
        'TalFlow Express</h1></td></tr>' +
        '<tr><td style="background:#1971C2;padding:14px;' +
        'text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:15px;' +
        'font-weight:bold;">New B2B Quote Request</p></td></tr>' +
        '<tr><td style="padding:32px 36px;">' +
        '<p style="color:#0A1628;font-size:15px;">' +
        'A new quote request has been submitted.</p>' +
        '<table width="100%" style="background:#F8F9FA;' +
        'border-radius:10px;margin:20px 0;">' +
        '<tr><td style="padding:16px 20px;">' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        '<strong>Quote:</strong> ' +
        quoteName +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        '<strong>Customer:</strong> ' +
        customerName +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        '<strong>Email:</strong> ' +
        customerEmail +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        '<strong>Items:</strong> ' +
        totalItems +
        '</p>' +
        '<p style="color:#495057;font-size:13px;margin:6px 0;">' +
        '<strong>Discount:</strong> ' +
        discountPercent +
        '%</p>' +
        '<p style="color:#FF6B1A;font-size:14px;' +
        'font-weight:bold;margin:12px 0 0;">' +
        'Total: $' +
        totalTTC.setScale(2) +
        '</p>' +
        (String.isNotBlank(comments)
          ? '<p style="color:#495057;font-size:13px;margin:12px 0;">' +
            '<strong>Comments:</strong> ' +
            comments +
            '</p>'
          : '') +
        '</td></tr></table>' +
        '<p style="color:#495057;font-size:14px;">' +
        'Please review in Salesforce and send to customer.</p>' +
        '<p style="color:#ADB5BD;font-size:11px;' +
        'text-align:center;margin-top:24px;">' +
        '© 2026 TalFlow Express</p>' +
        '</td></tr></table></body></html>';

      mail.setHtmlBody(htmlBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Admin quote email failed: ' + e.getMessage());
    }
  }

  private static void sendQuoteAcceptedEmail(
    String email,
    String firstName,
    String quoteName,
    Decimal totalTTC
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ email });
      mail.setSubject('TalFlow Express — Quote Accepted - Contract Created');
      mail.setSaveAsActivity(false);

      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine'
        LIMIT 1
      ];
      if (!owea.isEmpty()) {
        mail.setOrgWideEmailAddressId(owea[0].Id);
      }

      String htmlBody =
        '<html><body style="font-family:Arial,sans-serif;' +
        'background:#f4f4f4;padding:30px 0;">' +
        '<table width="600" align="center" style="background:#fff;' +
        'border-radius:12px;overflow:hidden;">' +
        '<tr><td style="background:#0A1628;padding:28px;' +
        'text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">' +
        'TalFlow Express</h1></td></tr>' +
        '<tr><td style="background:#1D9E75;padding:14px;' +
        'text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:15px;' +
        'font-weight:bold;">Quote Accepted!</p></td></tr>' +
        '<tr><td style="padding:32px 36px;">' +
        '<p style="color:#0A1628;">Hi <strong>' +
        firstName +
        '</strong>,</p>' +
        '<p style="color:#495057;font-size:14px;' +
        'line-height:1.7;">' +
        'You have accepted quote <strong>' +
        quoteName +
        '</strong> for <strong>$' +
        totalTTC.setScale(2) +
        '</strong>.</p>' +
        '<p style="color:#495057;font-size:14px;">' +
        'A contract has been created. Our team will ' +
        'contact you shortly to finalize the details.</p>' +
        '<p style="color:#ADB5BD;font-size:11px;' +
        'text-align:center;margin-top:24px;">' +
        '© 2026 TalFlow Express</p>' +
        '</td></tr></table></body></html>';

      mail.setHtmlBody(htmlBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Quote accepted email failed: ' + e.getMessage());
    }
  }

  // ── Wrappers ──────────────────────────────────────────────
  public class B2BProduct {
    @AuraEnabled
    public String productId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public Decimal b2bPrice;
    @AuraEnabled
    public String imageUrl;
    @AuraEnabled
    public Integer stock;
    @AuraEnabled
    public Integer quantity;
  }

  public class QuoteItem {
    @AuraEnabled
    public String productId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Integer quantity;
  }

  public class QuoteResult {
    @AuraEnabled
    public String quoteId;
    @AuraEnabled
    public String quoteName;
    @AuraEnabled
    public Decimal subtotal;
    @AuraEnabled
    public Decimal discountPercent;
    @AuraEnabled
    public Decimal discountAmount;
    @AuraEnabled
    public Decimal taxAmount;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public Integer totalItems;
  }

  public class QuoteSummary {
    @AuraEnabled
    public String quoteId;
    @AuraEnabled
    public String quoteName;
    @AuraEnabled
    public String quoteNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal grandTotal;
    @AuraEnabled
    public Decimal discountPercent;
    @AuraEnabled
    public String expirationDate;
    @AuraEnabled
    public String createdDate;
    @AuraEnabled
    public Integer itemCount;
  }

  public class QuoteDetail {
    @AuraEnabled
    public String quoteId;
    @AuraEnabled
    public String quoteName;
    @AuraEnabled
    public String quoteNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal subtotal;
    @AuraEnabled
    public Decimal grandTotal;
    @AuraEnabled
    public Decimal tax;
    @AuraEnabled
    public Decimal discountPercent;
    @AuraEnabled
    public Decimal discountAmount;
    @AuraEnabled
    public String expirationDate;
    @AuraEnabled
    public String createdDate;
    @AuraEnabled
    public String specialTerms;
    @AuraEnabled
    public String deliveryDate;
    @AuraEnabled
    public String shippingAddress;
    @AuraEnabled
    public String shippingCity;
    @AuraEnabled
    public String shippingCountry;
    @AuraEnabled
    public String shippingZip;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String oppName;
    @AuraEnabled
    public String oppStage;
    @AuraEnabled
    public String contactName;
    @AuraEnabled
    public String contactEmail;
    @AuraEnabled
    public List<QuoteItemDetail> items;
  }

  public class QuoteItemDetail {
    @AuraEnabled
    public String itemId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public String imageUrl;
    @AuraEnabled
    public Integer quantity;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Decimal totalPrice;
    @AuraEnabled
    public String description;
  }

  public class ContractSummary {
    @AuraEnabled
    public String contractId;
    @AuraEnabled
    public String contractNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public String quoteName;
    @AuraEnabled
    public String quoteNumber;
  }
}
