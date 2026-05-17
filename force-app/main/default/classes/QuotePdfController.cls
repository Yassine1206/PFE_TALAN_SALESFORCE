public without sharing class QuotePdfController {
  public Quote quote { get; private set; }
  public List<QuoteLineItem> quoteItems { get; private set; }
  public String accountName { get; private set; }
  public String contactName { get; private set; }
  public String contactEmail { get; private set; }

  public QuotePdfController() {
    Id quoteId = ApexPages.currentPage().getParameters().get('id');

    if (quoteId == null) {
      // Fallback to first Quote if no ID provided (for VF dev preview)
      List<Quote> quotes = [SELECT Id FROM Quote LIMIT 1];
      if (!quotes.isEmpty()) {
        quoteId = quotes[0].Id;
      }
    }

    if (quoteId == null) {
      quote = new Quote();
      quoteItems = new List<QuoteLineItem>();
      accountName = '—';
      contactName = '—';
      contactEmail = '—';
      return;
    }

    // Load Quote with all needed fields
    List<Quote> quotes = [
      SELECT
        Id,
        Name,
        QuoteNumber,
        Status,
        B2B_Status__c,
        CreatedDate,
        ExpirationDate,
        Subtotal,
        Discount,
        TotalPrice,
        GrandTotal,
        Special_Terms__c,
        Requested_Delivery_Date__c,
        Volume_Discount__c,
        Discount_Amount__c,
        ContactId,
        OpportunityId,
        Contact.FirstName,
        Contact.LastName,
        Contact.Email,
        Opportunity.AccountId,
        Opportunity.Account.Name,
        Opportunity.Account.ShippingCity,
        Opportunity.Account.ShippingCountry
      FROM Quote
      WHERE Id = :quoteId
      LIMIT 1
    ];

    if (quotes.isEmpty()) {
      quote = new Quote();
      quoteItems = new List<QuoteLineItem>();
      accountName = '—';
      contactName = '—';
      contactEmail = '—';
      return;
    }

    quote = quotes[0];

    // Load line items
    quoteItems = [
      SELECT
        Id,
        Quantity,
        UnitPrice,
        TotalPrice,
        Description,
        Product2.Id,
        Product2.Name,
        Product2.Family
      FROM QuoteLineItem
      WHERE QuoteId = :quoteId
      ORDER BY CreatedDate ASC
    ];

    // Build display strings
    accountName = (quote.Opportunity != null &&
      quote.Opportunity.Account != null)
      ? quote.Opportunity.Account.Name
      : '—';

    if (quote.Contact != null) {
      String fn = String.isNotBlank(quote.Contact.FirstName)
        ? quote.Contact.FirstName
        : '';
      String ln = String.isNotBlank(quote.Contact.LastName)
        ? quote.Contact.LastName
        : '';
      contactName = (fn + ' ' + ln).trim();
      contactEmail = String.isNotBlank(quote.Contact.Email)
        ? quote.Contact.Email
        : '—';
    } else {
      contactName = '—';
      contactEmail = '—';
    }
  }
}
