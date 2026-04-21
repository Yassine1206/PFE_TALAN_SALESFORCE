public without sharing class CkLeadQualifier {
    
    @InvocableMethod(
    label='Qualify B2B Lead'
        description='Convertit le Lead qualifié en Account + Contact + Opportunity'
        )
    public static List<String> qualifyLead(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return new List<String>();
        
        List<Lead> leads = [
        SELECT Id, Company FROM Lead WHERE Id IN :leadIds
    ];
        
        List<Lead> toUpdate = new List<Lead>();
        for (Lead l : leads) {
            l.Qualification_Score__c = 100;
            l.Status                 = 'Working - Contacted';
            toUpdate.add(l);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        
        // FIX : Queueable au lieu de @future — fonctionne depuis Agentforce
        System.enqueueJob(new CkLeadConversionJob(leadIds));
        
        List<String> results = new List<String>();
        for (Lead l : leads) {
            results.add('Lead ' + l.Company + ' qualified successfully.');
        }
        return results;
    }
    // @future
    // private static void convertLeadsAsync(List<Id> leadIds) {
        //     System.debug('=== convertLeadsAsync START === leads: ' + leadIds);
        
        //     List<Lead> leads = [
        //         SELECT Id, FirstName, LastName, Email, Company,
        //                Industry, NumberOfEmployees, Website,
        //                AnnualRevenue, Phone, Title, Description,
        //                B2B_Password_Hash__c, Qualification_Score__c,
        //                IsConverted
        //         FROM Lead WHERE Id IN :leadIds
        //     ];
        
        //     System.debug('Leads found: ' + leads.size());
        
        //     for (Lead l : leads) {
            //         try {
                //             // FIX : vérifier si déjà converti avant de continuer
                //             if (l.IsConverted) {
                    //                 System.debug('Lead already converted, skipping: ' + l.Id);
                    //                 continue;
                //             }
                
                //             System.debug('Processing: ' + l.Company + ' | ' + l.Email);
                
                //             Account acc           = new Account();
                //             acc.Name              = l.Company;
                //             acc.Industry          = l.Industry;
                //             acc.NumberOfEmployees = l.NumberOfEmployees;
                //             acc.Website           = l.Website;
                //             acc.AnnualRevenue     = l.AnnualRevenue;
                //             acc.Type              = 'Customer';
                //             acc.Description       = l.Description;
                //             insert acc;
                //             System.debug('Account created: ' + acc.Id);
                
                //             Contact con;
                //             List<Contact> existingCons = [
                //                 SELECT Id FROM Contact WHERE Email = :l.Email LIMIT 1
                //             ];
                //             if (!existingCons.isEmpty()) {
                    //                 con = existingCons[0];
                    //                 con.AccountId = acc.Id;
                    //                 update con;
                    //                 System.debug('Contact reused: ' + con.Id);
                //             } else {
                    //                 con                      = new Contact();
                    //                 con.FirstName            = l.FirstName;
                    //                 con.LastName             = l.LastName;
                    //                 con.Email                = l.Email;
                    //                 con.Phone                = l.Phone;
                    //                 con.Title                = l.Title;
                    //                 con.AccountId            = acc.Id;
                    //                 con.LeadSource           = 'Web';
                    //                 con.Is_Email_Verified__c = true;
                    //                 insert con;
                    //                 System.debug('Contact created: ' + con.Id);
                //             }
                
                //             Database.LeadConvert lc = new Database.LeadConvert();
                //             lc.setLeadId(l.Id);
                //             lc.setAccountId(acc.Id);
                //             lc.setContactId(con.Id);
                //             lc.setConvertedStatus('Closed - Converted');
                //             lc.setDoNotCreateOpportunity(true);
                //             Database.LeadConvertResult lcr = Database.convertLead(lc);
                //             System.debug('LeadConvert: ' + lcr.isSuccess());
                //             if (!lcr.isSuccess()) {
                    //                 for (Database.Error err : lcr.getErrors()) {
                        //                     System.debug('LeadConvert ERROR: ' + err.getMessage());
                    //                 }
                //             }
                
                //             Opportunity opp = new Opportunity();
                //             opp.Name        = l.Company + ' — B2B Opportunity';
                //             opp.AccountId   = acc.Id;
                //             opp.StageName   = 'Prospecting';
                //             opp.CloseDate   = Date.today().addDays(30);
                //             opp.LeadSource  = 'Web';
                //             opp.Description = 'Qualified by Agentforce\n'
                //                 + (l.Description != null ? l.Description : '');
                //             opp.Amount      = l.AnnualRevenue != null
                //                 ? l.AnnualRevenue * 0.1 : 0;
                //             insert opp;
                //             System.debug('Opportunity created: ' + opp.Id);
                
                //             if (String.isNotBlank(l.B2B_Password_Hash__c)) {
                    //                 System.enqueueJob(new CkB2BUserCreationJob(
                    //                     l.FirstName, l.LastName, l.Email,
                    //                 con.Id, l.Company, l.B2B_Password_Hash__c
                    //                     ));
                    //                 System.debug('UserCreationJob queued');
                //             }
                
                //             sendActivationEmail(l.Email, l.FirstName, l.Company);
                //             System.debug('Activation email sent');
                
            //         } catch (Exception e) {
                //             System.debug('ERREUR: ' + e.getMessage());
                //             System.debug('STACK: ' + e.getStackTraceString());
            //         }
        //     }
        //     System.debug('=== convertLeadsAsync END ===');
    // }
    
    private static void sendActivationEmail(
        String email, String firstName, String companyName
    ) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ email });
            mail.setSubject('Your TalFlow Express B2B Account is Activated!');
            mail.setSaveAsActivity(false);
            
            List<OrgWideEmailAddress> owea = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = 'Hasnaoui Yassine' LIMIT 1
            ];
            if (!owea.isEmpty()) mail.setOrgWideEmailAddressId(owea[0].Id);
            
            String htmlBody =
                '<html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:30px 0;">'
                + '<table width="600" align="center" style="background:#fff;border-radius:12px;overflow:hidden;">'
                + '<tr><td style="background:#0A1628;padding:28px;text-align:center;">'
                + '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">TalFlow Express</h1></td></tr>'
                + '<tr><td style="background:#1D9E75;padding:14px;text-align:center;">'
                + '<p style="color:#fff;margin:0;font-size:15px;font-weight:bold;">Account Activated!</p></td></tr>'
                + '<tr><td style="padding:32px 36px;">'
                + '<p style="color:#0A1628;">Hi <strong>' + firstName + '</strong>,</p>'
                + '<p style="color:#495057;font-size:14px;line-height:1.7;">'
                + 'Your B2B account for <strong>' + companyName + '</strong> '
                + 'has been approved by our AI qualification system.</p>'
                + '<table width="100%" style="background:#F8F9FA;border-radius:10px;margin:20px 0;">'
                + '<tr><td style="padding:16px 20px;">'
                + '<p style="color:#0A1628;font-weight:bold;margin:0 0 8px;">Next Steps</p>'
                + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Log in with your email and password</p>'
                + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ A sales rep will contact you shortly</p>'
                + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Explore our B2B catalog</p>'
                + '</td></tr></table>'
                + '<div style="text-align:center;margin-top:24px;">'
                + '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com/TalFlowExpress/s/login"'
                + ' style="background:#FF6B1A;color:#fff;padding:14px 32px;border-radius:10px;'
                + 'text-decoration:none;font-size:13px;font-weight:bold;">Sign In Now</a></div>'
                + '<p style="color:#ADB5BD;font-size:11px;text-align:center;margin-top:24px;">'
                + '© 2026 TalFlow Express</p>'
                + '</td></tr></table></body></html>';
            
            mail.setHtmlBody(htmlBody);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Activation email failed: ' + e.getMessage());
        }
    }
}