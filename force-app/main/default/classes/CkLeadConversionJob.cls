public class CkLeadConversionJob implements Queueable {
  private List<Id> leadIds;

  public CkLeadConversionJob(List<Id> leadIds) {
    this.leadIds = leadIds;
  }

  public void execute(QueueableContext context) {
    List<Lead> leads = [
      SELECT
        Id,
        FirstName,
        LastName,
        Email,
        Company,
        Industry,
        NumberOfEmployees,
        Website,
        AnnualRevenue,
        Phone,
        Title,
        Description,
        B2B_Password_Hash__c,
        Qualification_Score__c,
        IsConverted
      FROM Lead
      WHERE Id IN :leadIds
    ];

    for (Lead l : leads) {
      try {
        if (l.IsConverted) {
          System.debug('Already converted: ' + l.Id);
          continue;
        }

        System.debug('Processing: ' + l.Company);

        Account acc = new Account();
        acc.Name = l.Company;
        acc.Industry = l.Industry;
        acc.NumberOfEmployees = l.NumberOfEmployees;
        acc.Website = l.Website;
        acc.AnnualRevenue = l.AnnualRevenue;
        acc.Type = 'Customer';
        acc.Account_Type__c = 'B2B';
        acc.Description = l.Description;
        insert acc;
        System.debug('Account: ' + acc.Id);

        Contact con;
        List<Contact> existing = [
          SELECT Id
          FROM Contact
          WHERE Email = :l.Email
          LIMIT 1
        ];
        if (!existing.isEmpty()) {
          con = existing[0];
          con.AccountId = acc.Id;
          update con;
        } else {
          con = new Contact();
          con.FirstName = l.FirstName;
          con.LastName = l.LastName;
          con.Email = l.Email;
          con.Phone = l.Phone;
          con.Title = l.Title;
          con.AccountId = acc.Id;
          con.LeadSource = 'Web';
          con.Is_Email_Verified__c = true;
          insert con;
        }
        System.debug('Contact: ' + con.Id);

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setAccountId(acc.Id);
        lc.setContactId(con.Id);
        lc.setConvertedStatus('Closed - Converted');
        lc.setDoNotCreateOpportunity(true);
        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.debug('Converted: ' + lcr.isSuccess());

        Opportunity opp = new Opportunity();
        opp.Name = l.Company + ' — B2B Opportunity';
        opp.AccountId = acc.Id;
        opp.StageName = 'Prospecting';
        opp.CloseDate = Date.today().addDays(30);
        opp.LeadSource = 'Web';
        opp.Description =
          'Qualified by Agentforce\n' +
          (l.Description != null ? l.Description : '');
        opp.Amount = l.AnnualRevenue != null ? l.AnnualRevenue * 0.1 : 0;
        insert opp;
        System.debug('Opportunity: ' + opp.Id);

        if (String.isNotBlank(l.B2B_Password_Hash__c)) {
          System.enqueueJob(
            new CkB2BUserCreationJob(
              l.FirstName,
              l.LastName,
              l.Email,
              con.Id,
              l.Company,
              l.B2B_Password_Hash__c
            )
          );
        }

        sendActivationEmail(l.Email, l.FirstName, l.Company);
      } catch (Exception e) {
        System.debug('ERREUR: ' + e.getMessage());
        System.debug('STACK: ' + e.getStackTraceString());
      }
    }
  }

  private static void sendActivationEmail(
    String email,
    String firstName,
    String companyName
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ email });
      mail.setSubject('Your TalFlow Express B2B Account is Activated!');
      mail.setSaveAsActivity(false);
      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine'
        LIMIT 1
      ];
      if (!owea.isEmpty())
        mail.setOrgWideEmailAddressId(owea[0].Id);
      String htmlBody =
        '<html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:30px 0;">' +
        '<table width="600" align="center" style="background:#fff;border-radius:12px;overflow:hidden;">' +
        '<tr><td style="background:#0A1628;padding:28px;text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">TalFlow Express</h1></td></tr>' +
        '<tr><td style="background:#1D9E75;padding:14px;text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:15px;font-weight:bold;">Account Activated!</p></td></tr>' +
        '<tr><td style="padding:32px 36px;">' +
        '<p style="color:#0A1628;">Hi <strong>' +
        firstName +
        '</strong>,</p>' +
        '<p style="color:#495057;font-size:14px;line-height:1.7;">' +
        'Your B2B account for <strong>' +
        companyName +
        '</strong> ' +
        'has been approved by our AI qualification system.</p>' +
        '<div style="text-align:center;margin-top:24px;">' +
        '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com/TalFlowExpress/s/login"' +
        ' style="background:#FF6B1A;color:#fff;padding:14px 32px;border-radius:10px;' +
        'text-decoration:none;font-size:13px;font-weight:bold;">Sign In Now</a></div>' +
        '<p style="color:#ADB5BD;font-size:11px;text-align:center;margin-top:24px;">© 2026 TalFlow Express</p>' +
        '</td></tr></table></body></html>';
      mail.setHtmlBody(htmlBody);
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Email failed: ' + e.getMessage());
    }
  }
}
