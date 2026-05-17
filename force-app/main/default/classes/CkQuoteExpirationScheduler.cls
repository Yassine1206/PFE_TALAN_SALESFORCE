public without sharing class CkQuoteExpirationScheduler implements Schedulable, Database.Batchable<SObject>, Database.Stateful {
  // Counter for execution stats (Stateful keeps it across batches)
  private Integer totalExpired = 0;
  private Integer totalEmailsSent = 0;

  private static final String EXPIRED_TEMPLATE_NAME = 'B2B_Quote_Expired_1777641973005';
  private static final String OWEA_DISPLAY_NAME = 'Hasnaoui Yassine';

  // ═══════════════════════════════════════════════════════════
  // SCHEDULABLE — entry point called by the scheduler
  // ═══════════════════════════════════════════════════════════

  public void execute(SchedulableContext sc) {
    Database.executeBatch(new CkQuoteExpirationScheduler(), 50);
  }

  // ═══════════════════════════════════════════════════════════
  // BATCHABLE — Step 1 : Find expired quotes
  // ═══════════════════════════════════════════════════════════

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      'SELECT Id, QuoteNumber, B2B_Status__c, ContactId, ' +
        'Customer_Name__c, ExpirationDate, GrandTotal, ' +
        'Opportunity.Account.Name ' +
        'FROM Quote ' +
        'WHERE B2B_Status__c = \'Sent to Customer\' ' +
        'AND ExpirationDate < TODAY'
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BATCHABLE — Step 2 : Process each batch
  // ═══════════════════════════════════════════════════════════

  public void execute(Database.BatchableContext bc, List<Quote> scope) {
    if (scope.isEmpty())
      return;

    // 1. Update Quotes to 'Expired' (also populate Customer_Name__c if empty)
    List<Quote> toUpdate = new List<Quote>();
    for (Quote q : scope) {
      Quote updateQ = new Quote(Id = q.Id, B2B_Status__c = 'Expired');

      // Populate Customer_Name__c if not yet set
      String accountName = (q.Opportunity != null &&
        q.Opportunity.Account != null)
        ? q.Opportunity.Account.Name
        : '';
      if (
        String.isBlank(q.Customer_Name__c) && String.isNotBlank(accountName)
      ) {
        updateQ.Customer_Name__c = accountName;
      }

      toUpdate.add(updateQ);
    }

    try {
      update toUpdate;
      totalExpired += toUpdate.size();
      System.debug('✅ Marked ' + toUpdate.size() + ' quote(s) as Expired');
    } catch (Exception e) {
      System.debug('❌ Update failed: ' + e.getMessage());
      return;
    }

    // 2. Send "Quote Expired" emails via Lightning Email Template
    sendExpirationEmails(scope);
  }

  // ═══════════════════════════════════════════════════════════
  // BATCHABLE — Step 3 : Final summary
  // ═══════════════════════════════════════════════════════════

  public void finish(Database.BatchableContext bc) {
    System.debug('═══════════════════════════════════════');
    System.debug('🎯 Quote Expiration Job Finished');
    System.debug('   Quotes expired : ' + totalExpired);
    System.debug('   Emails sent    : ' + totalEmailsSent);
    System.debug('═══════════════════════════════════════');
  }

  // ═══════════════════════════════════════════════════════════
  // EMAIL via Lightning Email Template
  // ═══════════════════════════════════════════════════════════

  private void sendExpirationEmails(List<Quote> quotes) {
    // Find the email template
    List<EmailTemplate> tpls = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = :EXPIRED_TEMPLATE_NAME
      LIMIT 1
    ];
    if (tpls.isEmpty()) {
      System.debug('❌ Email template not found: ' + EXPIRED_TEMPLATE_NAME);
      return;
    }
    Id templateId = tpls[0].Id;

    // OrgWideEmailAddress
    List<OrgWideEmailAddress> oweaList = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE DisplayName = :OWEA_DISPLAY_NAME
      LIMIT 1
    ];
    Id oweaId = oweaList.isEmpty() ? null : oweaList[0].Id;

    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    for (Quote q : quotes) {
      if (q.ContactId == null) {
        System.debug('⚠️ No contact for Quote ' + q.Id + ' - skipping email');
        continue;
      }

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setTemplateId(templateId);
      mail.setTargetObjectId(q.ContactId);
      mail.setWhatId(q.Id);
      mail.setSaveAsActivity(false);
      mail.setTreatTargetObjectAsRecipient(true);

      if (oweaId != null) {
        mail.setOrgWideEmailAddressId(oweaId);
      }
      emails.add(mail);
    }

    if (!emails.isEmpty()) {
      try {
        Messaging.sendEmail(emails);
        totalEmailsSent += emails.size();
        System.debug('✅ Sent ' + emails.size() + ' expiration email(s)');
      } catch (Exception e) {
        System.debug('❌ Email send failed: ' + e.getMessage());
      }
    }
  }
}
