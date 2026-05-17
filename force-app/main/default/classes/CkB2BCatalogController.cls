public without sharing class CkB2BCatalogController {
  public class B2BProduct {
    @AuraEnabled
    public Id productId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String imageUrl { get; set; }
    @AuraEnabled
    public String categoryName { get; set; }
    @AuraEnabled
    public Id categoryId { get; set; }
    @AuraEnabled
    public Decimal b2bPrice { get; set; }
    @AuraEnabled
    public Decimal retailPrice { get; set; }
    @AuraEnabled
    public Decimal savings { get; set; }
    @AuraEnabled
    public Decimal stockQuantity { get; set; }
    @AuraEnabled
    public Decimal rating { get; set; }
    @AuraEnabled
    public Boolean isOnSale { get; set; }
    @AuraEnabled
    public Boolean isTopRated { get; set; }
    @AuraEnabled
    public Boolean inStock { get; set; }
  }

  public class CategoryOption {
    @AuraEnabled
    public Id categoryId { get; set; }
    @AuraEnabled
    public String categoryName { get; set; }
    @AuraEnabled
    public Integer productCount { get; set; }
  }

  public class FilterParams {
    @AuraEnabled
    public String searchTerm { get; set; }
    @AuraEnabled
    public Id categoryId { get; set; }
    @AuraEnabled
    public Decimal minPrice { get; set; }
    @AuraEnabled
    public Decimal maxPrice { get; set; }
    @AuraEnabled
    public Boolean inStockOnly { get; set; }
    @AuraEnabled
    public Boolean onSaleOnly { get; set; }
    @AuraEnabled
    public Boolean topRatedOnly { get; set; }
  }

  // ═══════════════════════════════════════════════════════════
  // GET PRODUCTS — Main catalog query
  // ═══════════════════════════════════════════════════════════
  @AuraEnabled(cacheable=true)
  public static List<B2BProduct> getProducts(FilterParams filters) {
    // Build dynamic SOQL
    String soql =
      'SELECT Id, Name, Image_URL__c, ' +
      'Stock_Quantity__c, Rating__c, Is_On_Sale__c, ' +
      'B2B_Price__c, Old_Price__c, ' +
      'Product_Category__c, Product_Category__r.Name ' +
      'FROM Product2 ' +
      'WHERE IsActive = true ' +
      'AND B2B_Price__c != null ' +
      'AND B2B_Price__c > 0 ';

    // Apply filters dynamically
    if (filters != null) {
      if (String.isNotBlank(filters.searchTerm)) {
        String search = '%' + filters.searchTerm + '%';
        soql += 'AND Name LIKE :search ';
      }
      if (filters.categoryId != null) {
        Id catId = filters.categoryId;
        soql += 'AND Product_Category__c = :catId ';
      }
      if (filters.minPrice != null && filters.minPrice > 0) {
        Decimal minP = filters.minPrice;
        soql += 'AND B2B_Price__c >= :minP ';
      }
      if (filters.maxPrice != null && filters.maxPrice > 0) {
        Decimal maxP = filters.maxPrice;
        soql += 'AND B2B_Price__c <= :maxP ';
      }
      if (filters.inStockOnly == true) {
        soql += 'AND Stock_Quantity__c > 0 ';
      }
      if (filters.onSaleOnly == true) {
        soql += 'AND Is_On_Sale__c = true ';
      }
      if (filters.topRatedOnly == true) {
        soql += 'AND Rating__c >= 4 ';
      }
    }

    soql += 'ORDER BY Name ASC LIMIT 100';

    // Need to alias param vars for binding to work in dynamic SOQL
    String search = (filters != null && String.isNotBlank(filters.searchTerm))
      ? '%' + filters.searchTerm + '%'
      : '%';
    Id catId = (filters != null) ? filters.categoryId : null;
    Decimal minP = (filters != null) ? filters.minPrice : null;
    Decimal maxP = (filters != null) ? filters.maxPrice : null;

    List<Product2> rawProducts = Database.query(soql);

    // Get retail prices from Standard Pricebook
    Map<Id, Decimal> retailPrices = getRetailPrices(rawProducts);

    // Build DTOs
    List<B2BProduct> result = new List<B2BProduct>();
    for (Product2 p : rawProducts) {
      B2BProduct dto = new B2BProduct();
      dto.productId = p.Id;
      dto.name = p.Name;
      dto.imageUrl = p.Image_URL__c;
      dto.categoryId = p.Product_Category__c;
      dto.categoryName = p.Product_Category__r != null
        ? p.Product_Category__r.Name
        : 'Uncategorized';
      dto.b2bPrice = p.B2B_Price__c;
      dto.retailPrice = retailPrices.get(p.Id);
      dto.savings = (dto.retailPrice != null)
        ? (dto.retailPrice - dto.b2bPrice).setScale(2)
        : 0;
      dto.stockQuantity = p.Stock_Quantity__c != null ? p.Stock_Quantity__c : 0;
      dto.rating = p.Rating__c != null ? p.Rating__c : 0;
      dto.isOnSale = p.Is_On_Sale__c == true;
      dto.isTopRated = (p.Rating__c != null && p.Rating__c >= 4);
      dto.inStock = (p.Stock_Quantity__c != null && p.Stock_Quantity__c > 0);

      result.add(dto);
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // GET CATEGORIES
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled(cacheable=true)
  public static List<CategoryOption> getCategories() {
    // Aggregate query: count products per category (only B2B products)
    AggregateResult[] grouped = [
      SELECT
        Product_Category__c catId,
        Product_Category__r.Name catName,
        COUNT(Id) cnt
      FROM Product2
      WHERE
        IsActive = TRUE
        AND B2B_Price__c != NULL
        AND B2B_Price__c > 0
        AND Product_Category__c != NULL
      GROUP BY Product_Category__c, Product_Category__r.Name
      ORDER BY Product_Category__r.Name ASC
    ];

    List<CategoryOption> result = new List<CategoryOption>();
    for (AggregateResult ar : grouped) {
      CategoryOption opt = new CategoryOption();
      opt.categoryId = (Id) ar.get('catId');
      opt.categoryName = (String) ar.get('catName');
      opt.productCount = (Integer) ar.get('cnt');
      result.add(opt);
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // ADD TO QUOTE REQUEST — Modal submit
  // ═══════════════════════════════════════════════════════════
  @AuraEnabled
  public static String submitQuickQuote(
    Id productId,
    Integer quantity,
    Date deliveryDate,
    String specialNotes,
    Boolean isUrgent,
    String urgencyReason
  ) {
    try {
      // Validate inputs
      if (productId == null) {
        throw new AuraHandledException('Product is required.');
      }
      if (quantity == null || quantity < 1) {
        throw new AuraHandledException('Quantity must be at least 1.');
      }

      // Get current user's account/contact
      User currentUser = [
        SELECT Id, ContactId, Contact.AccountId, Contact.Account.Name
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];

      if (currentUser.ContactId == null) {
        throw new AuraHandledException('No contact linked to this user.');
      }

      // Get product info
      Product2 product = [
        SELECT Id, Name, B2B_Price__c
        FROM Product2
        WHERE Id = :productId
        LIMIT 1
      ];

      // Get Standard Pricebook & PricebookEntry
      Pricebook2 standardPb = [
        SELECT Id
        FROM Pricebook2
        WHERE IsStandard = TRUE
        LIMIT 1
      ];

      List<PricebookEntry> entries = [
        SELECT Id
        FROM PricebookEntry
        WHERE
          Product2Id = :productId
          AND Pricebook2Id = :standardPb.Id
          AND IsActive = TRUE
        LIMIT 1
      ];

      if (entries.isEmpty()) {
        throw new AuraHandledException(
          'No pricebook entry found for this product.'
        );
      }

      // 1. Create Opportunity
      Opportunity opp = new Opportunity(
        Name = currentUser.Contact.Account.Name +
          ' — Quick Quote: ' +
          product.Name,
        AccountId = currentUser.Contact.AccountId,
        StageName = 'Quoting',
        CloseDate = Date.today().addDays(30),
        Pricebook2Id = standardPb.Id
      );
      insert opp;

      // 2. Create Quote
      Quote q = new Quote(
        Name = 'Quote for ' + product.Name,
        OpportunityId = opp.Id,
        Pricebook2Id = standardPb.Id,
        B2B_Status__c = 'Draft',
        Status = 'Draft',
        ExpirationDate = Date.today().addDays(30),
        ContactId = currentUser.ContactId,
        Special_Terms__c = String.isNotBlank(specialNotes)
          ? specialNotes
          : null,
        Requested_Delivery_Date__c = deliveryDate,
        Is_Urgent__c = (isUrgent != null && isUrgent),
        Urgency_Reason__c = (isUrgent == true &&
          String.isNotBlank(urgencyReason))
          ? urgencyReason
          : null
      );
      insert q;

      // 3. Create QuoteLineItem
      QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id,
        PricebookEntryId = entries[0].Id,
        Quantity = quantity,
        UnitPrice = product.B2B_Price__c
      );
      insert qli;

      // 4. Send notification email to admin
      sendAdminNotification(currentUser, product, quantity);

      return q.Id;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException('Error creating quote: ' + e.getMessage());
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════

  private static Map<Id, Decimal> getRetailPrices(List<Product2> products) {
    Set<Id> productIds = new Set<Id>();
    for (Product2 p : products) {
      productIds.add(p.Id);
    }

    Map<Id, Decimal> result = new Map<Id, Decimal>();
    if (productIds.isEmpty())
      return result;

    List<PricebookEntry> entries = [
      SELECT Product2Id, UnitPrice
      FROM PricebookEntry
      WHERE
        Product2Id IN :productIds
        AND Pricebook2.IsStandard = TRUE
        AND IsActive = TRUE
    ];

    for (PricebookEntry pbe : entries) {
      result.put(pbe.Product2Id, pbe.UnitPrice);
    }

    return result;
  }

  private static void sendAdminNotification(
    User customer,
    Product2 product,
    Integer quantity
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ 'hasnaouiyassine68@gmail.com' });
      mail.setSubject('🆕 New B2B Quick Quote Request');
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

      String body =
        '<html><body style="font-family:Arial;">' +
        '<h2 style="color:#FF6B1A;">New Quick Quote Request</h2>' +
        '<p>A B2B customer just submitted a quick quote.</p>' +
        '<table cellpadding="8" style="border-collapse:collapse;">' +
        '<tr><td><strong>Customer:</strong></td><td>' +
        customer.Contact.Account.Name +
        '</td></tr>' +
        '<tr><td><strong>Product:</strong></td><td>' +
        product.Name +
        '</td></tr>' +
        '<tr><td><strong>Quantity:</strong></td><td>' +
        quantity +
        '</td></tr>' +
        '<tr><td><strong>Unit Price:</strong></td><td>$' +
        product.B2B_Price__c +
        '</td></tr>' +
        '</table>' +
        '<p>Please review in Salesforce.</p>' +
        '</body></html>';

      mail.setHtmlBody(body);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Email notification failed: ' + e.getMessage());
    }
  }
}
