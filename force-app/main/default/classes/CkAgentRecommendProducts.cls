public without sharing class CkAgentRecommendProducts {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Number of recommendations'
      description='How many products to recommend (default 4, max 6)'
      required=false
    )
    public Integer maxResults;
  }

  public class Output {
    @InvocableVariable(label='Recommended products')
    public String recommendations;

    @InvocableVariable(label='Total recommendations')
    public Integer totalCount;
  }

  @InvocableMethod(
    label='Recommend Products for Customer'
    description='Returns personalized product recommendations based on customer purchase history'
    category='B2B Product Catalog'
  )
  public static List<Output> recommendProducts(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.recommendations = 'Unable to identify your account.';
      out.totalCount = 0;
      results.add(out);
      return results;
    }

    Integer maxResults = 4;
    if (inputs != null && !inputs.isEmpty() && inputs[0].maxResults != null) {
      maxResults = Math.min(inputs[0].maxResults, 6);
    }

    Set<Id> purchasedIds = new Set<Id>();
    for (OrderItem oi : [
      SELECT Product2Id
      FROM OrderItem
      WHERE Order.AccountId = :accountId
    ]) {
      if (oi.Product2Id != null)
        purchasedIds.add(oi.Product2Id);
    }

    Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);
    AggregateResult[] catResults = [
      SELECT Product2.Product_Category__c catId
      FROM OrderItem
      WHERE
        Order.AccountId = :accountId
        AND Order.EffectiveDate >= :startOfYear
        AND Product2.Product_Category__c != NULL
      GROUP BY Product2.Product_Category__c
      ORDER BY SUM(TotalPrice) DESC
      LIMIT 3
    ];

    Set<Id> topCategoryIds = new Set<Id>();
    for (AggregateResult r : catResults) {
      Id catId = (Id) r.get('catId');
      if (catId != null)
        topCategoryIds.add(catId);
    }

    List<Product2> recommended;
    if (!topCategoryIds.isEmpty()) {
      recommended = [
        SELECT Id, Name, B2B_Price__c, Rating__c, Product_Category__r.Name
        FROM Product2
        WHERE
          IsActive = TRUE
          AND B2B_Price__c != NULL
          AND Product_Category__c IN :topCategoryIds
          AND Id NOT IN :purchasedIds
        ORDER BY Rating__c DESC NULLS LAST
        LIMIT :maxResults
      ];
    } else {
      recommended = [
        SELECT Id, Name, B2B_Price__c, Rating__c, Product_Category__r.Name
        FROM Product2
        WHERE
          IsActive = TRUE
          AND B2B_Price__c != NULL
          AND Id NOT IN :purchasedIds
        ORDER BY Rating__c DESC NULLS LAST
        LIMIT :maxResults
      ];
    }

    Output out = new Output();
    if (recommended.isEmpty()) {
      out.recommendations = 'No new product recommendations at the moment.';
      out.totalCount = 0;
    } else {
      String summary =
        'Based on your purchase history, here are ' +
        recommended.size() +
        ' personalized recommendations:\n\n';
      for (Product2 p : recommended) {
        Decimal price = p.B2B_Price__c != null ? p.B2B_Price__c : 0;
        Decimal rating = p.Rating__c != null ? p.Rating__c : 0;
        String cat = p.Product_Category__r != null
          ? p.Product_Category__r.Name
          : 'Other';
        summary +=
          '• ' +
          p.Name +
          ' — $' +
          price.setScale(2).format() +
          ' — Category: ' +
          cat;
        if (rating > 0)
          summary += ' — Rating: ' + rating.setScale(1) + '/5';
        summary += '\n';
      }
      summary += '\nWould you like more details or to request a quote?';
      out.recommendations = summary;
      out.totalCount = recommended.size();
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
