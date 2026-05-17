public without sharing class CkAgentGetQuoteByNumber {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Quote Number'
      description='The quote number to look up (e.g., Q-006 or 00000006)'
      required=true
    )
    public String quoteNumber;
  }

  public class Output {
    @InvocableVariable(label='Quote details')
    public String quoteDetails;

    @InvocableVariable(label='Found')
    public Boolean found;
  }

  @InvocableMethod(
    label='Get Quote Details by Number'
    description='Returns full details of a specific quote by its quote number'
    category='B2B Quote Management'
  )
  public static List<Output> getQuoteByNumber(List<Input> inputs) {
    List<Output> results = new List<Output>();

    if (inputs == null || inputs.isEmpty()) {
      Output out = new Output();
      out.quoteDetails = 'No quote number provided.';
      out.found = false;
      results.add(out);
      return results;
    }

    Id accountId = resolveAccountId(inputs[0].contactId);
    if (accountId == null) {
      Output out = new Output();
      out.quoteDetails = 'Unable to identify your account.';
      out.found = false;
      results.add(out);
      return results;
    }

    String quoteNum = inputs[0].quoteNumber;
    String cleanedNum = quoteNum.trim()
      .replaceAll('(?i)q-?', '')
      .replaceAll('^0+', '');
    String likePattern = '%' + cleanedNum;

    List<Quote> quotes = [
      SELECT
        Id,
        QuoteNumber,
        CreatedDate,
        GrandTotal,
        B2B_Status__c,
        ExpirationDate,
        Volume_Discount__c,
        Discount_Amount__c,
        Special_Terms__c,
        Requested_Delivery_Date__c,
        (SELECT Id, Quantity, UnitPrice, Product2.Name FROM QuoteLineItems)
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND (QuoteNumber = :quoteNum
        OR QuoteNumber LIKE :likePattern)
      LIMIT 1
    ];

    Output out = new Output();
    if (quotes.isEmpty()) {
      out.quoteDetails =
        'Quote ' +
        quoteNum +
        ' was not found in your account.';
      out.found = false;
    } else {
      Quote q = quotes[0];
      Decimal amt = q.GrandTotal != null ? q.GrandTotal : 0;
      String dateStr = q.CreatedDate != null
        ? q.CreatedDate.date().format()
        : 'TBD';
      String status = q.B2B_Status__c != null ? q.B2B_Status__c : 'Draft';
      String expStr = q.ExpirationDate != null
        ? q.ExpirationDate.format()
        : 'No expiration';
      Decimal discount = q.Volume_Discount__c != null
        ? q.Volume_Discount__c
        : 0;
      Decimal discountAmt = q.Discount_Amount__c != null
        ? q.Discount_Amount__c
        : 0;

      String details = 'Quote ' + q.QuoteNumber + ' details:\n';
      details += '• Created: ' + dateStr + '\n';
      details += '• Total: $' + amt.setScale(2).format() + '\n';
      details += '• Status: ' + status + '\n';
      details += '• Expiration: ' + expStr + '\n';
      if (discount > 0) {
        details +=
          '• Volume discount: ' +
          discount.setScale(0) +
          '% ($' +
          discountAmt.setScale(0).format() +
          ' saved)\n';
      }
      if (q.Requested_Delivery_Date__c != null) {
        details +=
          '• Requested delivery: ' +
          q.Requested_Delivery_Date__c.format() +
          '\n';
      }
      if (String.isNotBlank(q.Special_Terms__c)) {
        details += '• Special terms: ' + q.Special_Terms__c + '\n';
      }

      if (!q.QuoteLineItems.isEmpty()) {
        details += '• Items (' + q.QuoteLineItems.size() + '):\n';
        for (QuoteLineItem qli : q.QuoteLineItems) {
          String prodName = qli.Product2 != null
            ? qli.Product2.Name
            : 'Unknown';
          Decimal qty = qli.Quantity != null ? qli.Quantity : 0;
          Decimal price = qli.UnitPrice != null ? qli.UnitPrice : 0;
          details +=
            '   - ' +
            prodName +
            ' (Qty: ' +
            qty.intValue() +
            ' × $' +
            price.setScale(2).format() +
            ')\n';
        }
      }

      out.quoteDetails = details;
      out.found = true;
    }
    results.add(out);
    return results;
  }

  private static Id resolveAccountId(String contactIdStr) {
    Id contactId = null;
    if (String.isNotBlank(contactIdStr)) {
      try {
        contactId = (Id) contactIdStr;
      } catch (Exception e) {
        System.debug('Invalid contactId string: ' + contactIdStr);
      }
    }
    if (contactId != null) {
      try {
        Contact c = [
          SELECT Id, AccountId
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        return c.AccountId;
      } catch (Exception e) {
        System.debug('Contact lookup failed: ' + e.getMessage());
      }
    }
    return null;
  }
}
