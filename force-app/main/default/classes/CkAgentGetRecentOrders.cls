public without sharing class CkAgentGetRecentOrders {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId after Customer Verification flow).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Number of orders to return'
      description='How many recent orders to fetch (default 5, max 10)'
      required=false
    )
    public Integer maxResults;
  }

  public class Output {
    @InvocableVariable(label='Order list summary')
    public String orderSummary;

    @InvocableVariable(label='Total orders count')
    public Integer totalCount;
  }

  @InvocableMethod(
    label='Get Customer Recent Orders'
    description='Returns the most recent orders of the verified B2B customer'
    category='B2B Order Management'
  )
  public static List<Output> getRecentOrders(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.orderSummary = 'Unable to identify your account. Please verify your identity first.';
      out.totalCount = 0;
      results.add(out);
      return results;
    }

    Integer maxResults = 5;
    if (inputs != null && !inputs.isEmpty() && inputs[0].maxResults != null) {
      maxResults = Math.min(inputs[0].maxResults, 10);
    }

    List<Order> orders = [
      SELECT Id, OrderNumber, EffectiveDate, TotalAmount, Status
      FROM Order
      WHERE AccountId = :accountId
      ORDER BY EffectiveDate DESC NULLS LAST
      LIMIT :maxResults
    ];

    Output out = new Output();
    if (orders.isEmpty()) {
      out.orderSummary = 'You have no orders yet. Browse our catalog to start ordering.';
      out.totalCount = 0;
    } else {
      String summary =
        'Here are your ' +
        orders.size() +
        ' most recent orders:\n\n';
      for (Order o : orders) {
        Decimal amt = o.TotalAmount != null ? o.TotalAmount : 0;
        String dateStr = o.EffectiveDate != null
          ? o.EffectiveDate.format()
          : 'TBD';
        summary +=
          '• ' +
          o.OrderNumber +
          ' — $' +
          amt.setScale(0).format() +
          ' — Date: ' +
          dateStr +
          ' — Status: ' +
          o.Status +
          '\n';
      }
      out.orderSummary = summary;
      out.totalCount = orders.size();
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
