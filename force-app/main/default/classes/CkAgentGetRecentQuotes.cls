public without sharing class CkAgentGetRecentQuotes {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Status filter (optional)'
      description='Filter quotes by B2B status: Draft, Sent to Customer, Accepted, Rejected, Expired.'
      required=false
    )
    public String statusFilter;
  }

  public class Output {
    @InvocableVariable(label='Quotes summary')
    public String quotesSummary;

    @InvocableVariable(label='Total quotes count')
    public Integer totalCount;
  }

  @InvocableMethod(
    label='Get Customer Recent Quotes'
    description='Returns the recent quotes of the verified B2B customer, optionally filtered by status'
    category='B2B Quote Management'
  )
  public static List<Output> getRecentQuotes(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.quotesSummary = 'Unable to identify your account.';
      out.totalCount = 0;
      results.add(out);
      return results;
    }

    String statusFilter = null;
    if (
      inputs != null &&
      !inputs.isEmpty() &&
      String.isNotBlank(inputs[0].statusFilter)
    ) {
      statusFilter = inputs[0].statusFilter.trim();
    }

    List<Quote> quotes;
    if (statusFilter != null) {
      quotes = [
        SELECT
          Id,
          QuoteNumber,
          CreatedDate,
          GrandTotal,
          B2B_Status__c,
          ExpirationDate,
          Volume_Discount__c
        FROM Quote
        WHERE
          Opportunity.AccountId = :accountId
          AND B2B_Status__c = :statusFilter
        ORDER BY CreatedDate DESC
        LIMIT 5
      ];
    } else {
      quotes = [
        SELECT
          Id,
          QuoteNumber,
          CreatedDate,
          GrandTotal,
          B2B_Status__c,
          ExpirationDate,
          Volume_Discount__c
        FROM Quote
        WHERE Opportunity.AccountId = :accountId
        ORDER BY CreatedDate DESC
        LIMIT 5
      ];
    }

    Output out = new Output();
    if (quotes.isEmpty()) {
      out.quotesSummary = statusFilter != null
        ? 'You have no quotes with status "' + statusFilter + '".'
        : 'You have no quotes yet.';
      out.totalCount = 0;
    } else {
      String summary = 'Here are your ' + quotes.size() + ' recent quotes';
      if (statusFilter != null)
        summary += ' (filtered by ' + statusFilter + ')';
      summary += ':\n\n';

      for (Quote q : quotes) {
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

        summary +=
          '• ' +
          q.QuoteNumber +
          ' — $' +
          amt.setScale(0).format() +
          ' — Status: ' +
          status +
          ' — Created: ' +
          dateStr +
          ' — Expires: ' +
          expStr;
        if (discount > 0)
          summary += ' — Discount: ' + discount.setScale(0) + '%';
        summary += '\n';
      }
      out.quotesSummary = summary;
      out.totalCount = quotes.size();
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
