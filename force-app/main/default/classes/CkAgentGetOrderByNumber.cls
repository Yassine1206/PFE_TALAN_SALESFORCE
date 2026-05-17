public without sharing class CkAgentGetOrderByNumber {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Order Number'
      description='The order number to look up (e.g., ORD-001 or 00000123)'
      required=true
    )
    public String orderNumber;
  }

  public class Output {
    @InvocableVariable(label='Order details')
    public String orderDetails;

    @InvocableVariable(label='Found')
    public Boolean found;
  }

  @InvocableMethod(
    label='Get Order Details by Number'
    description='Returns full details of a specific order by its order number'
    category='B2B Order Management'
  )
  public static List<Output> getOrderByNumber(List<Input> inputs) {
    List<Output> results = new List<Output>();

    if (inputs == null || inputs.isEmpty()) {
      Output out = new Output();
      out.orderDetails = 'No order number provided.';
      out.found = false;
      results.add(out);
      return results;
    }

    Id accountId = resolveAccountId(inputs[0].contactId);
    if (accountId == null) {
      Output out = new Output();
      out.orderDetails = 'Unable to identify your account.';
      out.found = false;
      results.add(out);
      return results;
    }

    String orderNum = inputs[0].orderNumber;
    String cleanedNum = orderNum.trim()
      .replaceAll('(?i)ord-?', '')
      .replaceAll('^0+', '');
    String likePattern = '%' + cleanedNum;

    List<Order> orders = [
      SELECT
        Id,
        OrderNumber,
        EffectiveDate,
        TotalAmount,
        Status,
        (SELECT Id, Quantity, UnitPrice, Product2.Name FROM OrderItems)
      FROM Order
      WHERE
        AccountId = :accountId
        AND (OrderNumber = :orderNum
        OR OrderNumber LIKE :likePattern)
      LIMIT 1
    ];

    Output out = new Output();
    if (orders.isEmpty()) {
      out.orderDetails =
        'Order ' +
        orderNum +
        ' was not found in your account.';
      out.found = false;
    } else {
      Order o = orders[0];
      Decimal amt = o.TotalAmount != null ? o.TotalAmount : 0;
      String dateStr = o.EffectiveDate != null
        ? o.EffectiveDate.format()
        : 'TBD';

      String details = 'Order ' + o.OrderNumber + ' details:\n';
      details += '• Date: ' + dateStr + '\n';
      details += '• Total: $' + amt.setScale(2).format() + '\n';
      details += '• Status: ' + o.Status + '\n';

      if (!o.OrderItems.isEmpty()) {
        details += '• Items (' + o.OrderItems.size() + '):\n';
        for (OrderItem oi : o.OrderItems) {
          String prodName = oi.Product2 != null ? oi.Product2.Name : 'Unknown';
          Decimal qty = oi.Quantity != null ? oi.Quantity : 0;
          Decimal price = oi.UnitPrice != null ? oi.UnitPrice : 0;
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
      out.orderDetails = details;
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
