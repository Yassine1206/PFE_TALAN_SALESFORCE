public without sharing class CkContractSignatureController {
  public class SignatureWrapper {
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String contractNumber;
    @AuraEnabled
    public Boolean alreadySigned;
    @AuraEnabled
    public String signedByName;
    @AuraEnabled
    public DateTime signedDate;
    @AuraEnabled
    public String signatureImage;
  }

  /**
   * @description Returns signature status for a given contract.
   */
  @AuraEnabled(cacheable=true)
  public static SignatureWrapper getSignatureStatus(Id contractId) {
    SignatureWrapper result = new SignatureWrapper();

    if (contractId == null)
      return result;

    List<Contract> contracts = [
      SELECT
        Id,
        ContractNumber,
        Signature_Image__c,
        Signed_Date__c,
        Signed_By_Name__c
      FROM Contract
      WHERE Id = :contractId
      LIMIT 1
    ];

    if (contracts.isEmpty())
      return result;

    Contract c = contracts[0];
    result.contractId = c.Id;
    result.contractNumber = c.ContractNumber;
    result.alreadySigned = String.isNotBlank(c.Signature_Image__c);
    result.signedByName = c.Signed_By_Name__c;
    result.signedDate = c.Signed_Date__c;
    result.signatureImage = c.Signature_Image__c;

    return result;
  }

  /**
   * @description Saves the signature on the contract.
   * @param contractId The contract to sign
   * @param signatureBase64 The base64-encoded PNG signature image
   * @param signedByName Full name of the signer (for legal trace)
   */
  @AuraEnabled
  public static Contract saveSignature(
    Id contractId,
    String signatureBase64,
    String signedByName
  ) {
    if (contractId == null) {
      throw new AuraHandledException('Contract ID is required.');
    }

    if (String.isBlank(signatureBase64)) {
      throw new AuraHandledException('Signature is required.');
    }

    if (String.isBlank(signedByName)) {
      throw new AuraHandledException('Signer name is required.');
    }

    // Strip "data:image/png;base64," prefix if present
    if (signatureBase64.startsWith('data:image')) {
      signatureBase64 = signatureBase64.substringAfter(',');
    }

    Contract c;
    try {
      c = [
        SELECT
          Id,
          ContractNumber,
          AccountId,
          Status,
          Signature_Image__c,
          Signed_Date__c
        FROM Contract
        WHERE Id = :contractId
        LIMIT 1
      ];
    } catch (Exception e) {
      throw new AuraHandledException('Contract not found.');
    }

    if (String.isNotBlank(c.Signature_Image__c)) {
      throw new AuraHandledException('Contract is already signed.');
    }

    c.Signature_Image__c = signatureBase64;
    c.Signed_Date__c = System.now();
    c.Signed_By_Name__c = signedByName;
    c.Status = 'Activated';

    try {
      update c;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to save signature: ' + e.getMessage()
      );
    }

    // Régénérer le PDF du contrat avec la signature embedded
    try {
      CkPdfService.generateAndSaveContractPdf(contractId);
      System.debug('✅ Contract PDF regenerated with signature');
    } catch (Exception e) {
      System.debug('⚠️ Failed to regenerate PDF: ' + e.getMessage());
      // Pas critique : l'utilisateur peut toujours re-télécharger plus tard
    }

    // Create a notification for the customer (confirmation)
    try {
      Id userId = UserInfo.getUserId();
      CkNotificationController.createNotification(
        userId,
        '✅ Contract Signed',
        'You have successfully signed contract C-' +
          c.ContractNumber +
          '. ' +
          'A signed copy is available in your contracts.',
        'Success',
        '/TalFlowExpress/s/my-contracts',
        'document'
      );
    } catch (Exception e) {
      System.debug('Failed to create notification: ' + e.getMessage());
    }
    // 🎯 Notify Sales Manager + Admin when contract is signed
    try {
      Contract signed = [
        SELECT Id, ContractNumber, Total_Amount__c, Account.Name
        FROM Contract
        WHERE Id = :contractId
        LIMIT 1
      ];

      Set<Id> recipients = CkInternalNotificationService.getAdminUserIds();
      recipients.addAll(
        CkInternalNotificationService.getUsersByRole('Sales_Manager')
      );

      Decimal amt = signed.Total_Amount__c != null ? signed.Total_Amount__c : 0;

      CkInternalNotificationService.send(
        CkInternalNotificationService.TYPE_CONTRACT_SIGNED,
        '✍️ Contract Signed',
        signed.Account.Name +
          ' signed contract C-' +
          signed.ContractNumber +
          ' ($' +
          amt.setScale(0).format() +
          ').',
        recipients,
        signed.Id
      );
    } catch (Exception e) {
      System.debug(
        'Failed to send contract signed notification: ' + e.getMessage()
      );
    }
    return c;
  }
  public class ContractSignatureSummary {
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
    @AuraEnabled
    public Boolean isSigned;
    @AuraEnabled
    public String signedByName;
    @AuraEnabled
    public DateTime signedDate;
    @AuraEnabled
    public String customerName;
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractSignatureSummary> getMyContractsWithSignature() {
    try {
      String userId = UserInfo.getUserId();
      User u = [
        SELECT ContactId, Contact.AccountId, Contact.FirstName, Contact.LastName
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null) {
        return new List<ContractSignatureSummary>();
      }

      String customerName = '';
      if (u.Contact != null) {
        customerName =
          (u.Contact.FirstName != null ? u.Contact.FirstName : '') +
          ' ' +
          (u.Contact.LastName != null ? u.Contact.LastName : '');
        customerName = customerName.trim();
      }

      List<Contract> contracts = [
        SELECT
          Id,
          ContractNumber,
          Status,
          StartDate,
          EndDate,
          ContractTerm,
          Total_Amount__c,
          Signature_Image__c,
          Signed_Date__c,
          Signed_By_Name__c,
          Quote__r.Name,
          Quote__r.QuoteNumber,
          CreatedDate
        FROM Contract
        WHERE AccountId = :u.Contact.AccountId
        ORDER BY CreatedDate DESC
      ];

      List<ContractSignatureSummary> result = new List<ContractSignatureSummary>();
      for (Contract c : contracts) {
        ContractSignatureSummary cs = new ContractSignatureSummary();
        cs.contractId = c.Id;
        cs.contractNumber = c.ContractNumber;
        cs.status = c.Status;
        cs.startDate = c.StartDate != null ? c.StartDate.format() : '';
        cs.endDate = c.EndDate != null ? c.EndDate.format() : '';
        cs.totalAmount = c.Total_Amount__c;
        cs.quoteName = c.Quote__r != null ? c.Quote__r.Name : '';
        cs.quoteNumber = c.Quote__r != null ? c.Quote__r.QuoteNumber : '';
        cs.isSigned = String.isNotBlank(c.Signature_Image__c);
        cs.signedByName = c.Signed_By_Name__c;
        cs.signedDate = c.Signed_Date__c;
        cs.customerName = customerName;
        result.add(cs);
      }

      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
