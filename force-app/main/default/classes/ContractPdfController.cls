public without sharing class ContractPdfController {
  public Contract contractRecord { get; private set; }
  public Quote sourceQuote { get; private set; }
  public List<QuoteLineItem> contractItems { get; private set; }
  public String accountName { get; private set; }
  public String accountAddress { get; private set; }
  public String contactName { get; private set; }
  public String contactEmail { get; private set; }
  public String contractStartDateStr { get; private set; }
  public String contractEndDateStr { get; private set; }
  public String signedDateStr { get; private set; }

  public ContractPdfController() {
    Id contractId = ApexPages.currentPage().getParameters().get('id');

    if (contractId == null) {
      List<Contract> contracts = [SELECT Id FROM Contract LIMIT 1];
      if (!contracts.isEmpty()) {
        contractId = contracts[0].Id;
      }
    }

    if (contractId == null) {
      initEmpty();
      return;
    }

    // Load Contract with all needed fields
    List<Contract> contracts = [
      SELECT
        Id,
        ContractNumber,
        Status,
        StartDate,
        ContractTerm,
        EndDate,
        Total_Amount__c,
        Quote__c,
        AccountId,
        Account.Name,
        Account.ShippingStreet,
        Account.ShippingCity,
        Account.ShippingPostalCode,
        Account.ShippingCountry,
        CreatedDate,
        Signature_Image__c,
        Signed_Date__c,
        Signed_By_Name__c
      FROM Contract
      WHERE Id = :contractId
      LIMIT 1
    ];

    if (contracts.isEmpty()) {
      initEmpty();
      return;
    }

    contractRecord = contracts[0];

    // Load source Quote (if Quote__c is set)
    if (contractRecord.Quote__c != null) {
      List<Quote> quotes = [
        SELECT
          Id,
          Name,
          QuoteNumber,
          GrandTotal,
          Subtotal,
          ContactId,
          Contact.FirstName,
          Contact.LastName,
          Contact.Email
        FROM Quote
        WHERE Id = :contractRecord.Quote__c
        LIMIT 1
      ];
      if (!quotes.isEmpty()) {
        sourceQuote = quotes[0];

        // Load line items from the source quote
        contractItems = [
          SELECT Id, Quantity, UnitPrice, TotalPrice, Product2.Id, Product2.Name
          FROM QuoteLineItem
          WHERE QuoteId = :sourceQuote.Id
          ORDER BY CreatedDate ASC
        ];
      } else {
        contractItems = new List<QuoteLineItem>();
      }
    } else {
      sourceQuote = new Quote();
      contractItems = new List<QuoteLineItem>();
    }

    // Build display strings
    accountName = (contractRecord.Account != null)
      ? contractRecord.Account.Name
      : '—';

    // Build address
    String addr = '';
    if (contractRecord.Account != null) {
      if (String.isNotBlank(contractRecord.Account.ShippingStreet)) {
        addr += contractRecord.Account.ShippingStreet + ', ';
      }
      if (String.isNotBlank(contractRecord.Account.ShippingCity)) {
        addr += contractRecord.Account.ShippingCity + ', ';
      }
      if (String.isNotBlank(contractRecord.Account.ShippingPostalCode)) {
        addr += contractRecord.Account.ShippingPostalCode + ' ';
      }
      if (String.isNotBlank(contractRecord.Account.ShippingCountry)) {
        addr += contractRecord.Account.ShippingCountry;
      }
    }
    accountAddress = String.isBlank(addr) ? '—' : addr.removeEnd(', ');

    if (sourceQuote != null && sourceQuote.Contact != null) {
      String fn = String.isNotBlank(sourceQuote.Contact.FirstName)
        ? sourceQuote.Contact.FirstName
        : '';
      String ln = String.isNotBlank(sourceQuote.Contact.LastName)
        ? sourceQuote.Contact.LastName
        : '';
      contactName = (fn + ' ' + ln).trim();
      contactEmail = String.isNotBlank(sourceQuote.Contact.Email)
        ? sourceQuote.Contact.Email
        : '—';
    } else {
      contactName = '—';
      contactEmail = '—';
    }

    // Format dates
    if (contractRecord.StartDate != null) {
      contractStartDateStr = contractRecord.StartDate.format();
    } else {
      contractStartDateStr = '—';
    }

    if (contractRecord.EndDate != null) {
      contractEndDateStr = contractRecord.EndDate.format();
    } else {
      contractEndDateStr = '—';
    }
    // Format signed date
    if (contractRecord.Signed_Date__c != null) {
      signedDateStr = contractRecord.Signed_Date__c.format();
    } else {
      signedDateStr = '';
    }
  }

  private void initEmpty() {
    contractRecord = new Contract();
    sourceQuote = new Quote();
    contractItems = new List<QuoteLineItem>();
    accountName = '—';
    accountAddress = '—';
    contactName = '—';
    contactEmail = '—';
    contractStartDateStr = '—';
    contractEndDateStr = '—';
    signedDateStr = '';
  }
}
