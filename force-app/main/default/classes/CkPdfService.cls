public without sharing class CkPdfService {
  // ═══════════════════════════════════════════════════════════
  // INVOICE PDF
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled
  public static String getInvoicePdfUrl(String orderId) {
    try {
      List<Order> orders = [SELECT Id FROM Order WHERE Id = :orderId LIMIT 1];
      if (orders.isEmpty()) {
        throw new AuraHandledException('Order not found.');
      }
      return '/TalFlowExpress/apex/InvoicePdfPage?id=' + orderId;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ═══════════════════════════════════════════════════════════
  // QUOTE PDF
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled
  public static String getQuotePdfUrl(String quoteId) {
    try {
      if (String.isBlank(quoteId)) {
        throw new AuraHandledException('Quote Id is required.');
      }

      List<Quote> quotes = [SELECT Id FROM Quote WHERE Id = :quoteId LIMIT 1];
      if (quotes.isEmpty()) {
        throw new AuraHandledException('Quote not found.');
      }

      // Look for existing PDF (linked to this Quote)
      ContentDocument doc = getLatestPdfDocument(quoteId, 'Quote');

      if (doc == null) {
        // Generate fresh PDF and store
        generateAndSaveQuotePdf(quoteId);
        doc = getLatestPdfDocument(quoteId, 'Quote');
      }

      if (doc == null) {
        throw new AuraHandledException('Failed to generate PDF.');
      }

      // Return Salesforce content download URL
      return '/TalFlowExpress/sfc/servlet.shepherd/version/download/' +
        doc.LatestPublishedVersionId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching Quote PDF: ' + e.getMessage()
      );
    }
  }

  public static String generateAndSaveQuotePdf(String quoteId) {
    try {
      // 1. Delete existing PDFs linked to this Quote
      deleteExistingPdfs(quoteId, 'Quote');

      // 2. Get Quote info for filename
      Quote q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :quoteId LIMIT 1];
      String quoteNumber = String.isNotBlank(q.QuoteNumber)
        ? q.QuoteNumber
        : 'DRAFT';
      String fileName = 'Quote-' + quoteNumber;

      // 3. Generate PDF blob via Visualforce
      PageReference pdfPage = Page.QuotePdfPage;
      pdfPage.getParameters().put('id', quoteId);

      Blob pdfBlob;
      if (Test.isRunningTest()) {
        pdfBlob = Blob.valueOf('Test Quote PDF Content');
      } else {
        pdfBlob = pdfPage.getContentAsPDF();
      }

      // 4. Create ContentVersion + auto-link via FirstPublishLocationId
      ContentVersion cv = new ContentVersion();
      cv.Title = fileName;
      cv.PathOnClient = fileName + '.pdf';
      cv.VersionData = pdfBlob;
      cv.FirstPublishLocationId = quoteId;
      cv.IsMajorVersion = true;
      insert cv;

      ContentVersion savedCv = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        LIMIT 1
      ];

      return savedCv.ContentDocumentId;
    } catch (Exception e) {
      System.debug('Quote PDF generation failed: ' + e.getMessage());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CONTRACT PDF
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled
  public static String getContractPdfUrl(String contractId) {
    try {
      if (String.isBlank(contractId)) {
        throw new AuraHandledException('Contract Id is required.');
      }

      List<Contract> contracts = [
        SELECT Id
        FROM Contract
        WHERE Id = :contractId
        LIMIT 1
      ];
      if (contracts.isEmpty()) {
        throw new AuraHandledException('Contract not found.');
      }

      ContentDocument doc = getLatestPdfDocument(contractId, 'Contract');

      if (doc == null) {
        generateAndSaveContractPdf(contractId);
        doc = getLatestPdfDocument(contractId, 'Contract');
      }

      if (doc == null) {
        throw new AuraHandledException('Failed to generate PDF.');
      }

      return '/TalFlowExpress/sfc/servlet.shepherd/version/download/' +
        doc.LatestPublishedVersionId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching Contract PDF: ' + e.getMessage()
      );
    }
  }

  public static String generateAndSaveContractPdf(String contractId) {
    try {
      deleteExistingPdfs(contractId, 'Contract');

      Contract c = [
        SELECT Id, ContractNumber
        FROM Contract
        WHERE Id = :contractId
        LIMIT 1
      ];
      String contractNumber = String.isNotBlank(c.ContractNumber)
        ? c.ContractNumber
        : 'DRAFT';
      String fileName = 'Contract-' + contractNumber;

      PageReference pdfPage = Page.ContractPdfPage;
      pdfPage.getParameters().put('id', contractId);

      Blob pdfBlob;
      if (Test.isRunningTest()) {
        pdfBlob = Blob.valueOf('Test Contract PDF Content');
      } else {
        pdfBlob = pdfPage.getContentAsPDF();
      }

      ContentVersion cv = new ContentVersion();
      cv.Title = fileName;
      cv.PathOnClient = fileName + '.pdf';
      cv.VersionData = pdfBlob;
      cv.FirstPublishLocationId = contractId;
      cv.IsMajorVersion = true;
      insert cv;

      ContentVersion savedCv = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        LIMIT 1
      ];

      return savedCv.ContentDocumentId;
    } catch (Exception e) {
      System.debug('Contract PDF generation failed: ' + e.getMessage());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════

  private static ContentDocument getLatestPdfDocument(
    Id recordId,
    String prefix
  ) {
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :recordId
    ];

    if (links.isEmpty())
      return null;

    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink l : links) {
      docIds.add(l.ContentDocumentId);
    }

    List<ContentDocument> docs = [
      SELECT Id, Title, LatestPublishedVersionId, CreatedDate
      FROM ContentDocument
      WHERE Id IN :docIds AND Title LIKE :(prefix + '-%')
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    return docs.isEmpty() ? null : docs[0];
  }

  private static void deleteExistingPdfs(Id recordId, String prefix) {
    try {
      List<ContentDocumentLink> links = [
        SELECT ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :recordId
      ];

      if (links.isEmpty())
        return;

      Set<Id> docIds = new Set<Id>();
      for (ContentDocumentLink l : links) {
        docIds.add(l.ContentDocumentId);
      }

      List<ContentDocument> oldDocs = [
        SELECT Id
        FROM ContentDocument
        WHERE Id IN :docIds AND Title LIKE :(prefix + '-%')
      ];

      if (!oldDocs.isEmpty()) {
        delete oldDocs;
        System.debug(
          '🗑️ Deleted ' + oldDocs.size() + ' old PDF(s) for ' + prefix
        );
      }
    } catch (Exception e) {
      System.debug('⚠️ Error deleting old PDFs: ' + e.getMessage());
    }
  }
}
