/**
 * @description Schedulable class that runs every hour to check urgent quote SLA status.
 * - Identifies urgent quotes nearing SLA expiration (Warning) or past SLA (Breach)
 * - Sends notifications + emails to Sales Manager and Admin
 * - Updates SLA_Breached__c flag on breached quotes
 *
 * Schedule with:
 *   System.schedule('CkSLAEscalationHourly_00', '0 0 * * * ?', new CkSLAEscalationScheduler());
 *   ... (one for each minute or use Apex API)
 */
public without sharing class CkSLAEscalationScheduler implements Schedulable {
  public void execute(SchedulableContext sc) {
    runSLACheck();
  }

  /**
   * @description Main SLA check logic. Can be called manually for testing.
   */
  public static void runSLACheck() {
    DateTime now = System.now();
    DateTime warningThreshold = now.addHours(2); // SLA Due Date within 2h → Warning

    // 🔍 Query all urgent quotes not yet responded and not yet marked as breached
    List<Quote> urgentQuotes = [
      SELECT
        Id,
        QuoteNumber,
        GrandTotal,
        CreatedDate,
        SLA_Due_Date__c,
        Is_Urgent__c,
        Urgency_Reason__c,
        B2B_Status__c,
        SLA_Breached__c,
        Opportunity.Account.Name
      FROM Quote
      WHERE
        Is_Urgent__c = TRUE
        AND B2B_Status__c = 'Draft'
        AND SLA_Breached__c = FALSE
    ];

    if (urgentQuotes.isEmpty()) {
      System.debug('✅ SLA Check: No urgent quotes to process');
      return;
    }

    System.debug(
      '🔍 SLA Check: Processing ' + urgentQuotes.size() + ' urgent quotes'
    );

    // Categorize quotes
    List<Quote> breachQuotes = new List<Quote>();
    List<Quote> warningQuotes = new List<Quote>();

    for (Quote q : urgentQuotes) {
      if (q.SLA_Due_Date__c == null)
        continue;

      if (q.SLA_Due_Date__c <= now) {
        // 🔴 SLA breached (past due date)
        breachQuotes.add(q);
      } else if (q.SLA_Due_Date__c <= warningThreshold) {
        // 🟠 SLA warning (within 2h of due date)
        warningQuotes.add(q);
      }
      // Else : still on time, no action
    }

    System.debug(
      '🔴 Breached: ' +
        breachQuotes.size() +
        ' | 🟠 Warnings: ' +
        warningQuotes.size()
    );

    // Process Warnings
    if (!warningQuotes.isEmpty()) {
      processWarnings(warningQuotes);
    }

    // Process Breaches
    if (!breachQuotes.isEmpty()) {
      processBreaches(breachQuotes);
    }
  }

  /**
   * @description Send warning notifications for quotes nearing SLA expiry.
   */
  private static void processWarnings(List<Quote> warningQuotes) {
    Set<Id> salesManagers = CkInternalNotificationService.getUsersByRole(
      'Sales_Manager'
    );
    if (salesManagers.isEmpty()) {
      System.debug('No Sales Manager found for warning notifications');
      return;
    }

    for (Quote q : warningQuotes) {
      String accountName = q.Opportunity?.Account?.Name != null
        ? q.Opportunity.Account.Name
        : 'Customer';
      String amount = q.GrandTotal != null
        ? '$' + q.GrandTotal.setScale(0).format()
        : '';

      CkInternalNotificationService.send(
        CkInternalNotificationService.TYPE_URGENT_QUOTE,
        '⚠️ SLA Warning — ' + q.QuoteNumber,
        accountName +
          ' urgent quote (' +
          amount +
          ') expires in less than 2 hours. ACT NOW.',
        salesManagers,
        q.Id
      );
    }

    System.debug('⚠️ Sent ' + warningQuotes.size() + ' warning notifications');
  }

  /**
   * @description Process SLA breaches: critical notifications + escalation emails + flag update.
   */
  private static void processBreaches(List<Quote> breachQuotes) {
    // Get all recipients (Sales Manager + Admin for escalation)
    Set<Id> salesManagers = CkInternalNotificationService.getUsersByRole(
      'Sales_Manager'
    );
    Set<Id> admins = CkInternalNotificationService.getAdminUserIds();
    Set<Id> allRecipients = new Set<Id>();
    allRecipients.addAll(salesManagers);
    allRecipients.addAll(admins);

    if (allRecipients.isEmpty()) {
      System.debug('No recipients for breach escalation');
      return;
    }

    List<Quote> quotesToUpdate = new List<Quote>();

    for (Quote q : breachQuotes) {
      String accountName = q.Opportunity?.Account?.Name != null
        ? q.Opportunity.Account.Name
        : 'Customer';
      String amount = q.GrandTotal != null
        ? '$' + q.GrandTotal.setScale(0).format()
        : '';

      // Critical notification to Sales Manager + Admin
      CkInternalNotificationService.send(
        CkInternalNotificationService.TYPE_URGENT_QUOTE,
        '🔴 SLA BREACHED — ' + q.QuoteNumber,
        accountName +
          ' urgent quote (' +
          amount +
          ') exceeded 24h SLA. ESCALATION required.',
        allRecipients,
        q.Id
      );

      // Send escalation email
      sendBreachEmail(q, accountName, amount);

      // Mark as breached
      quotesToUpdate.add(new Quote(Id = q.Id, SLA_Breached__c = true));
    }

    // Bulk update breached quotes
    if (!quotesToUpdate.isEmpty()) {
      try {
        update quotesToUpdate;
        System.debug(
          '✅ Marked ' + quotesToUpdate.size() + ' quotes as SLA breached'
        );
      } catch (Exception e) {
        System.debug('Failed to update SLA breached quotes: ' + e.getMessage());
      }
    }
  }

  /**
   * @description Send critical escalation email for SLA breach.
   */
  private static void sendBreachEmail(
    Quote q,
    String accountName,
    String amount
  ) {
    try {
      // Get Sales Manager + Admin emails
      List<User> recipients = [
        SELECT Email
        FROM User
        WHERE
          (UserRole.DeveloperName = 'Sales_Manager'
          OR Profile.Name = 'System Administrator')
          AND IsActive = TRUE
          AND Email != NULL
      ];

      if (recipients.isEmpty())
        return;

      Set<String> toAddressSet = new Set<String>();
      for (User u : recipients)
        toAddressSet.add(u.Email);
      List<String> toAddresses = new List<String>(toAddressSet);

      String reasonHtml = String.isNotBlank(q.Urgency_Reason__c)
        ? '<tr><td style="padding:8px 0;color:#495057;font-size:13px;width:130px;"><strong>Reason:</strong></td><td style="color:#0A1628;font-size:13px;">' +
          q.Urgency_Reason__c +
          '</td></tr>'
        : '';

      String htmlBody =
        '<html><body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:30px 0;">' +
        '<tr><td align="center">' +
        '<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 16px rgba(0,0,0,0.1);">' +
        // Header
        '<tr><td style="background:#0A1628;padding:24px;text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;letter-spacing:1px;">TalFlow Express</h1>' +
        '<p style="color:#fff;margin:8px 0 0;font-size:13px;">SLA Management System</p>' +
        '</td></tr>' +
        // Critical banner
        '<tr><td style="background:#8B0000;padding:18px;text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:20px;font-weight:bold;">🔴 SLA BREACHED — CRITICAL</p>' +
        '<p style="color:#fff;margin:8px 0 0;font-size:12px;opacity:0.9;">Urgent quote exceeded 24-hour response window</p>' +
        '</td></tr>' +
        // Body
        '<tr><td style="padding:32px 28px;">' +
        '<p style="color:#0A1628;font-size:15px;margin:0 0 16px;">Critical alert,</p>' +
        '<p style="color:#495057;font-size:14px;line-height:1.6;margin:0 0 20px;">' +
        'The urgent quote below has <strong style="color:#E24B4A;">NOT been responded to within the 24-hour SLA</strong>. ' +
        'This is a service-level violation that requires immediate attention to preserve the customer relationship.</p>' +
        // Quote details
        '<table width="100%" cellpadding="0" cellspacing="0" style="background:#FFE5E5;border:2px solid #E24B4A;border-radius:10px;margin-bottom:20px;">' +
        '<tr><td style="padding:18px 22px;">' +
        '<p style="color:#8B0000;margin:0 0 14px;font-size:14px;font-weight:bold;">⚠️ Breach Details</p>' +
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;width:130px;"><strong>Quote Number:</strong></td><td style="color:#0A1628;font-size:13px;font-weight:bold;">' +
        q.QuoteNumber +
        '</td></tr>' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;"><strong>Customer:</strong></td><td style="color:#0A1628;font-size:13px;">' +
        accountName +
        '</td></tr>' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;"><strong>Amount:</strong></td><td style="color:#0A1628;font-size:13px;font-weight:bold;">' +
        amount +
        '</td></tr>' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;"><strong>Submitted:</strong></td><td style="color:#0A1628;font-size:13px;">' +
        q.CreatedDate.format('yyyy-MM-dd HH:mm') +
        '</td></tr>' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;"><strong>SLA Deadline:</strong></td><td style="color:#E24B4A;font-size:13px;font-weight:bold;">' +
        q.SLA_Due_Date__c.format('yyyy-MM-dd HH:mm') +
        '</td></tr>' +
        '<tr><td style="padding:8px 0;color:#495057;font-size:13px;"><strong>Status:</strong></td><td style="color:#8B0000;font-size:13px;font-weight:bold;">🔴 BREACHED</td></tr>' +
        reasonHtml +
        '</table>' +
        '</td></tr></table>' +
        // Actions
        '<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F8FF;border:1.5px solid #B8D4F0;border-radius:10px;margin-bottom:24px;">' +
        '<tr><td style="padding:16px 20px;">' +
        '<p style="color:#0A1628;margin:0 0 10px;font-size:13px;font-weight:bold;">📋 Recommended Actions</p>' +
        '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Contact the customer immediately</p>' +
        '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Send the formal quote within the next hour</p>' +
        '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Document the reason for delay in Activity History</p>' +
        '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Notify the customer with a follow-up email</p>' +
        '</td></tr></table>' +
        // CTA
        '<table width="100%" cellpadding="0" cellspacing="0">' +
        '<tr><td align="center">' +
        '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.salesforce.com/' +
        q.Id +
        '" ' +
        'style="display:inline-block;background:#8B0000;color:#fff;padding:14px 36px;border-radius:10px;text-decoration:none;font-size:13px;font-weight:bold;">' +
        'View Quote in Salesforce →</a>' +
        '</td></tr></table>' +
        '</td></tr>' +
        // Footer
        '<tr><td style="background:#0A1628;padding:20px 28px;text-align:center;">' +
        '<p style="color:#FF6B1A;font-size:12px;font-weight:bold;margin:0 0 4px;">TalFlow Express</p>' +
        '<p style="color:#868E96;font-size:11px;margin:0;">Automated SLA Breach Alert</p>' +
        '</td></tr>' +
        '</table></td></tr></table>' +
        '</body></html>';

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        LIMIT 1
      ];
      if (!owea.isEmpty())
        mail.setOrgWideEmailAddressId(owea[0].Id);

      mail.setToAddresses(toAddresses);
      mail.setSubject(
        '🔴 CRITICAL: SLA BREACHED on Quote ' +
          q.QuoteNumber +
          ' — ' +
          accountName
      );
      mail.setHtmlBody(htmlBody);
      mail.setSaveAsActivity(false);

      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
      System.debug('✅ SLA breach email sent for Quote ' + q.QuoteNumber);
    } catch (Exception e) {
      System.debug('Failed to send breach email: ' + e.getMessage());
    }
  }
}
