public without sharing class CkLeadController {

    // ── 1. Statut du Lead (appelé depuis LWC) ─────────────────
    @AuraEnabled
    public static LeadStatus getLeadStatus(String email) {
        try {
            LeadStatus status = new LeadStatus();

            List<Lead> leads = [
                SELECT Id, Status, FirstName, LastName, Company,
                       Qualification_Score__c, Rejection_Reason__c,
                       IsConverted, ConvertedAccountId
                FROM Lead
                WHERE Email = :email
                AND IsConverted = false
                ORDER BY CreatedDate DESC LIMIT 1
            ];

            if (leads.isEmpty()) {
                status.found = false;
                return status;
            }

            Lead l             = leads[0];
            status.found       = true;
            status.leadId      = l.Id;
            status.leadStatus  = l.Status;
            status.score       = l.Qualification_Score__c != null
                ? l.Qualification_Score__c.intValue() : 0;
            status.isConverted = l.IsConverted;
            status.rejectionReason = l.Rejection_Reason__c;

            return status;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 2. Créer User B2B (@future — appelé depuis CkLeadQualifier)
    // public car appelé depuis une autre classe
    @future
    public static void createB2BUserAsync(
        String firstName, String lastName, String email,
        String contactId, String companyName, String passwordHash
    ) {
        try {
            List<Profile> profiles = [
                SELECT Id FROM Profile
                WHERE Name = 'Customer Community User' LIMIT 1
            ];
            if (profiles.isEmpty()) {
                profiles = [
                    SELECT Id FROM Profile
                    WHERE Name = 'External Identity User' LIMIT 1
                ];
            }
            if (profiles.isEmpty()) return;

            String alias = '';
            if (String.isNotBlank(firstName))
                alias += firstName.substring(0, 1);
            if (String.isNotBlank(lastName))
                alias += lastName.substring(0, Math.min(7, lastName.length()));

            User newUser              = new User();
            newUser.FirstName         = firstName;
            newUser.LastName          = lastName;
            newUser.Email             = email;
            newUser.Username          = email;
            newUser.ContactId         = Id.valueOf(contactId);
            newUser.ProfileId         = profiles[0].Id;
            newUser.Alias             = alias.toLowerCase();
            newUser.EmailEncodingKey  = 'UTF-8';
            newUser.LanguageLocaleKey = 'en_US';
            newUser.LocaleSidKey      = 'en_US';
            newUser.TimeZoneSidKey    = 'Africa/Tunis';
            newUser.CompanyName       = companyName;
            newUser.CommunityNickname = email.split('@')[0]
                + String.valueOf(Math.round(Math.random() * 9999));
            newUser.IsActive          = true;
            insert newUser;

            // Appliquer le mot de passe
            String password = EncodingUtil.base64Decode(passwordHash).toString();
            System.setPassword(newUser.Id, password);

            // Assigner Permission Set
            List<PermissionSet> ps = [
                SELECT Id FROM PermissionSet
                WHERE Name = 'Community_Customer_Access' LIMIT 1
            ];
            if (!ps.isEmpty()) {
                insert new PermissionSetAssignment(
                    PermissionSetId = ps[0].Id,
                    AssigneeId      = newUser.Id
                );
            }

        } catch (Exception e) {
            System.debug('B2B User creation failed: ' + e.getMessage());
        }
    }

    // ── Wrappers ──────────────────────────────────────────────
    public class LeadStatus {
        @AuraEnabled public Boolean found          = false;
        @AuraEnabled public String  leadId;
        @AuraEnabled public String  leadStatus;
        @AuraEnabled public Integer score;
        @AuraEnabled public Boolean isConverted    = false;
        @AuraEnabled public String  rejectionReason;
    }
}