public without sharing class CkLeadRejector {
    
    @InvocableMethod(
    label='Reject B2B Lead'
        description='Rejette le Lead non qualifié et envoie un email'
        )
    public static List<String> rejectLead(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return new List<String>();
        
        List<Lead> leads = [
            SELECT Id, FirstName, Email, Company,
                   Qualification_Score__c
            FROM Lead WHERE Id IN :leadIds
        ];
        
        List<Lead> toUpdate = new List<Lead>();
        for (Lead l : leads) {
            // Agentforce a décidé de rejeter → score = 0
            l.Qualification_Score__c = 0;
            l.Status                 = 'Closed - Not Converted';
            // FIX : pas de variable score — utiliser message fixe
            l.Rejection_Reason__c    = 'Rejected by Agentforce AI — insufficient business profile.';
            toUpdate.add(l);
            sendRejectionEmail(l.Email, l.FirstName, l.Company);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        
        List<String> results = new List<String>();
        for (Lead l : leads) {
            results.add('Lead ' + l.Company + ' rejected by Agentforce.');
        }
        return results;
    }
    
    private static void sendRejectionEmail(
        String email, String firstName, String companyName
    ) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ email });
            mail.setSubject('TalFlow Express — B2B Application Update');
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
                + '<tr><td style="padding:32px 36px;">'
                + '<p style="color:#0A1628;">Hi <strong>' + firstName + '</strong>,</p>'
                + '<p style="color:#495057;font-size:14px;line-height:1.7;">'
                + 'Thank you for applying to TalFlow Express B2B Program. '
                + 'After reviewing your application for <strong>' + companyName + '</strong>, '
                + 'we are unable to approve your account at this time.</p>'
                + '<p style="color:#495057;font-size:14px;line-height:1.7;">'
                + 'You are welcome to reapply with more complete business information.</p>'
                + '<p style="color:#ADB5BD;font-size:11px;text-align:center;margin-top:24px;">© 2026 TalFlow Express</p>'
                + '</td></tr></table></body></html>';
            
            mail.setHtmlBody(htmlBody);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Rejection email failed: ' + e.getMessage());
        }
    }
}