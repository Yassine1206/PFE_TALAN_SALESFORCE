/**
 * Controller for My Invoices B2B page.
 * Returns invoices with full details, status badges, filters.
 */
public with sharing class CkInvoiceController {
  public class InvoiceSummary {
    @AuraEnabled
    public Id invoiceId;
    @AuraEnabled
    public String invoiceNumber;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal totalTTC;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String invoiceDate;
    @AuraEnabled
    public String dueDate;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String statusClass;
    @AuraEnabled
    public Boolean isOverdue;
  }

  public class InvoiceDetail {
    @AuraEnabled
    public Id invoiceId;
    @AuraEnabled
    public String invoiceNumber;
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
    public String orderNumber;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String countryCode;
    @AuraEnabled
    public String invoiceDate;
    @AuraEnabled
    public String dueDate;
    @AuraEnabled
    public String accountName;
  }

  /**
   * @description Returns all invoices for the current B2B customer.
   */
  @AuraEnabled(cacheable=true)
  public static List<InvoiceSummary> getMyInvoices() {
    try {
      Id userId = UserInfo.getUserId();
      User u = [
        SELECT ContactId, Contact.AccountId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null || u.Contact.AccountId == null) {
        return new List<InvoiceSummary>();
      }

      List<Invoice__c> invoices = [
        SELECT
          Id,
          Name,
          Invoice_Number__c,
          Status__c,
          Total_TTC__c,
          Payment_Method__c,
          CreatedDate,
          Order__c,
          Order__r.OrderNumber
        FROM Invoice__c
        WHERE
          Account__c = :u.Contact.AccountId
          OR Order__r.AccountId = :u.Contact.AccountId
        ORDER BY CreatedDate DESC
      ];

      Date today = Date.today();
      List<InvoiceSummary> result = new List<InvoiceSummary>();

      for (Invoice__c i : invoices) {
        InvoiceSummary s = new InvoiceSummary();
        s.invoiceId = i.Id;
        s.invoiceNumber = String.isNotBlank(i.Invoice_Number__c)
          ? i.Invoice_Number__c
          : i.Name;
        s.name = i.Name;
        s.status = i.Status__c;
        s.totalTTC = i.Total_TTC__c != null ? i.Total_TTC__c : 0;
        s.orderId = i.Order__c;
        s.orderNumber = i.Order__r != null ? i.Order__r.OrderNumber : '';
        s.invoiceDate = i.CreatedDate != null
          ? i.CreatedDate.date().format()
          : '';

        // Due date = CreatedDate + 30 days (Net 30)
        Date due = i.CreatedDate != null
          ? i.CreatedDate.date().addDays(30)
          : null;
        s.dueDate = due != null ? due.format() : '';

        s.paymentMethod = i.Payment_Method__c;
        s.statusClass = getStatusClass(i.Status__c);

        // Overdue if unpaid AND past due date
        s.isOverdue = (i.Status__c != 'Paid' && due != null && today > due);

        result.add(s);
      }

      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Returns full details of a specific invoice.
   */
  @AuraEnabled(cacheable=true)
  public static InvoiceDetail getInvoiceDetail(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Invoice ID required');
    }

    Id userId = UserInfo.getUserId();
    User u = [
      SELECT ContactId, Contact.AccountId
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];

    List<Invoice__c> invoices = [
      SELECT
        Id,
        Name,
        Invoice_Number__c,
        Status__c,
        Subtotal__c,
        Tax_Amount__c,
        Tax_Rate__c,
        Shipping_Cost__c,
        Discount__c,
        Total_TTC__c,
        Payment_Method__c,
        Country_Code__c,
        CreatedDate,
        Order__c,
        Order__r.OrderNumber,
        Order__r.Account.Name
      FROM Invoice__c
      WHERE Id = :invoiceId
      LIMIT 1
    ];

    if (invoices.isEmpty()) {
      throw new AuraHandledException('Invoice not found');
    }

    Invoice__c i = invoices[0];
    InvoiceDetail d = new InvoiceDetail();
    d.invoiceId = i.Id;
    d.invoiceNumber = String.isNotBlank(i.Invoice_Number__c)
      ? i.Invoice_Number__c
      : i.Name;
    d.status = i.Status__c;
    d.subtotal = i.Subtotal__c != null ? i.Subtotal__c : 0;
    d.taxAmount = i.Tax_Amount__c != null ? i.Tax_Amount__c : 0;
    d.taxRate = i.Tax_Rate__c != null ? i.Tax_Rate__c : 0;
    d.shippingCost = i.Shipping_Cost__c != null ? i.Shipping_Cost__c : 0;
    d.discount = i.Discount__c != null ? i.Discount__c : 0;
    d.totalTTC = i.Total_TTC__c != null ? i.Total_TTC__c : 0;
    d.orderId = i.Order__c;
    d.orderNumber = i.Order__r != null ? i.Order__r.OrderNumber : '';
    d.accountName = i.Order__r != null &&
      i.Order__r.Account != null
      ? i.Order__r.Account.Name
      : '';
    d.paymentMethod = i.Payment_Method__c;
    d.countryCode = i.Country_Code__c;
    d.invoiceDate = i.CreatedDate != null ? i.CreatedDate.date().format() : '';

    Date due = i.CreatedDate != null ? i.CreatedDate.date().addDays(30) : null;
    d.dueDate = due != null ? due.format() : '';

    return d;
  }

  /**
   * @description Returns aggregate stats for the invoices dashboard cards.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getMyInvoicesStats() {
    Map<String, Object> stats = new Map<String, Object>{
      'totalInvoices' => 0,
      'totalPaid' => 0,
      'unpaidAmount' => 0,
      'overdueCount' => 0
    };

    try {
      Id userId = UserInfo.getUserId();
      User u = [
        SELECT ContactId, Contact.AccountId
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null || u.Contact.AccountId == null)
        return stats;

      Id accountId = u.Contact.AccountId;

      // Total invoices
      Integer total = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE Account__c = :accountId OR Order__r.AccountId = :accountId
      ];
      stats.put('totalInvoices', total);

      // Total paid (sum)
      AggregateResult[] paidResult = [
        SELECT SUM(Total_TTC__c) total
        FROM Invoice__c
        WHERE
          (Account__c = :accountId
          OR Order__r.AccountId = :accountId)
          AND Status__c = 'Paid'
      ];
      Decimal paid = !paidResult.isEmpty() && paidResult[0].get('total') != null
        ? (Decimal) paidResult[0].get('total')
        : 0;
      stats.put('totalPaid', paid);

      // Unpaid amount
      AggregateResult[] unpaidResult = [
        SELECT SUM(Total_TTC__c) total
        FROM Invoice__c
        WHERE
          (Account__c = :accountId
          OR Order__r.AccountId = :accountId)
          AND Status__c != 'Paid'
      ];
      Decimal unpaid = !unpaidResult.isEmpty() &&
        unpaidResult[0].get('total') != null
        ? (Decimal) unpaidResult[0].get('total')
        : 0;
      stats.put('unpaidAmount', unpaid);

      // Overdue count (unpaid + CreatedDate + 30 < today)
      DateTime cutoff = DateTime.newInstance(
        Date.today().addDays(-30),
        Time.newInstance(0, 0, 0, 0)
      );
      Integer overdue = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          (Account__c = :accountId
          OR Order__r.AccountId = :accountId)
          AND Status__c != 'Paid'
          AND CreatedDate < :cutoff
      ];
      stats.put('overdueCount', overdue);

      return stats;
    } catch (Exception e) {
      return stats;
    }
  }

  private static String getStatusClass(String status) {
    if (status == 'Paid')
      return 'inv-status-paid';
    if (status == 'Sent')
      return 'inv-status-sent';
    if (status == 'Draft')
      return 'inv-status-draft';
    return 'inv-status-default';
  }
}
