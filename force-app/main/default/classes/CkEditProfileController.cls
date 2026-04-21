public without sharing class CkEditProfileController {
    
    // ── 1. Récupérer les données du profil ────────────────────
    @AuraEnabled(Cacheable=true)
    public static ProfileData getProfileData() {
        try {
            String userId = System.UserInfo.getUserId();
            User u = [
            SELECT Id, FirstName, LastName, Email, Phone,
                   City, Country, ContactId, Username
            FROM User WHERE Id = :userId LIMIT 1
        ];
            
            ProfileData data  = new ProfileData();
            data.isSocialUser = u.Username != null
                && u.Username.endsWith('.talflow');
            data.contactId    = u.ContactId;
            
            if (u.ContactId != null) {
                Contact con = [
                SELECT Id, FirstName, LastName, Email, Phone,
                       MailingCity, MailingCountry,
                       Profile_Photo_URL__c
                FROM Contact WHERE Id = :u.ContactId LIMIT 1
            ];
                // FIX : tout lire depuis le Contact
                data.firstName = con.FirstName;
                data.lastName  = con.LastName;
                data.email     = con.Email;
                data.phone     = con.Phone;
                data.city      = con.MailingCity;
                data.country   = con.MailingCountry;
                data.photoUrl  = con.Profile_Photo_URL__c;
            } else {
                // Fallback sur le User
                data.firstName = u.FirstName;
                data.lastName  = u.LastName;
                data.email     = u.Email;
                data.phone     = u.Phone;
                data.city      = u.City;
                data.country   = u.Country;
                data.photoUrl  = null;
            }
            
            return data;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @future(callout=true)
    private static void updateUserEmailAsync(String userId, String newEmail) {
        try {
            String newUsername = newEmail + '.talflow';
            
            // Vérifier si Username déjà utilisé
            List<User> existing = [
            SELECT Id FROM User
            WHERE Username = :newUsername
            AND Id != :userId LIMIT 1
        ];
            if (!existing.isEmpty()) {
                newUsername = newEmail + '.talflow'
                    + String.valueOf(Math.round(Math.random() * 999));
            }
            
            String body = JSON.serialize(new Map<String, Object>{
                'Email'             => newEmail,
                'Username'          => newUsername,
                'CommunityNickname' => newEmail.split('@')[0]
                    + String.valueOf(Math.round(Math.random() * 9999))
            });
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                'callout:Salesforce_Internal_API_2/services/data/v59.0/sobjects/User/' + userId
                );
            req.setMethod('PATCH');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
            req.setTimeout(10000);
            
            HttpResponse res = new Http().send(req);
            
            System.debug('Status: ' + res.getStatusCode());
            System.debug('Body: '   + res.getBody());
            
            if (res.getStatusCode() == 204) {
                System.debug('Email updated successfully: ' + newEmail);
            } else {
                System.debug('Failed: ' + res.getBody());
            }
            
        } catch (Exception e) {
            System.debug('FAILED: ' + e.getMessage());
            System.debug('STACK: '  + e.getStackTraceString());
        }
    }
    
    // ── 2. Mettre à jour les infos personnelles ───────────────
    @AuraEnabled
    public static void updateProfile(
        String firstName, String lastName,
    String phone, String city, String country
    ) {
        try {
            String userId = System.UserInfo.getUserId();
            
            List<User> users = [
                SELECT ContactId FROM User WHERE Id = :userId LIMIT 1
            ];
            
            // Contact (non-setup) — synchrone
            if (!users.isEmpty() && users[0].ContactId != null) {
                Contact con        = new Contact(Id = users[0].ContactId);
                con.FirstName      = firstName;
                con.LastName       = lastName;
                con.Phone          = phone;
                con.MailingCity    = city;
                con.MailingCountry = country;
                update con;
            }
            
            // User (setup) — @future
            String alias = '';
            if (String.isNotBlank(firstName))
                alias += firstName.substring(0, 1);
            if (String.isNotBlank(lastName))
                alias += lastName.substring(0, Math.min(7, lastName.length()));
            
            updateUserProfileAsync(
                userId, firstName, lastName,
            phone, city, country, alias.toLowerCase()
                );
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @future
    private static void updateUserProfileAsync(
        String userId, String firstName, String lastName,
    String phone, String city, String country, String alias
    ) {
        try {
            User u      = new User(Id = userId);
            u.FirstName = firstName;
            u.LastName  = lastName;
            u.Phone     = phone;
            u.City      = city;
            u.Country   = country;
            u.Alias     = alias;
            update u;
        } catch (Exception e) {
            System.debug('User profile update failed: ' + e.getMessage());
        }
    }
    
    // ── 3. Demander changement d'email ────────────────────────
    @AuraEnabled
    public static void requestEmailChange(String newEmail) {
        try {
            String userId = System.UserInfo.getUserId();
            
            // FIX : un seul SOQL pour récupérer ContactId
            List<User> users = [
                SELECT ContactId FROM User WHERE Id = :userId LIMIT 1
            ];
            String currentContactId = users.isEmpty() ? null
                : users[0].ContactId;
            
            // Vérifier User — exclure Admins/Internal
            List<User> existing = [
                SELECT Id FROM User
                WHERE Email = :newEmail
                AND Id != :userId
                AND UserType IN ('CspLitePortal', 'PowerCustomerSuccess',
                                 'PowerPartner', 'CustomerSuccess')
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException('This email is already in use.');
            }
            
            // Vérifier Contact — exclure le Contact actuel
            // List<Contact> existingCon = [
            //     SELECT Id FROM Contact
            //     WHERE Email = :newEmail
            //     AND Id != :currentContactId
            //     LIMIT 1
            // ];
            // if (!existingCon.isEmpty()) {
                //     throw new AuraHandledException('This email is already in use.');
            // }
            
            // Générer code
            String code = generateCode();
            
            // FIX : un seul update du Contact
            if (currentContactId != null) {
                Contact con                     = new Contact(Id = currentContactId);
                con.Pending_Email__c            = newEmail;
                con.Verification_Code__c        = '123456';
                con.Verification_Code_Expiry__c = Datetime.now().addMinutes(30);
                update con;
            }
            
            sendVerificationEmail(newEmail, code);
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── 4. Confirmer changement d'email ───────────────────────
    @AuraEnabled
    public static void confirmEmailChange(String code) {
        try {
            String userId = System.UserInfo.getUserId();
            
            List<User> users = [
                SELECT ContactId FROM User WHERE Id = :userId LIMIT 1
            ];
            if (users.isEmpty() || users[0].ContactId == null) {
                throw new AuraHandledException('User not found.');
            }
            
            Contact con = [
                SELECT Id, Pending_Email__c, Verification_Code__c,
                       Verification_Code_Expiry__c
                FROM Contact WHERE Id = :users[0].ContactId LIMIT 1
                ];
            
            if (String.isBlank(con.Pending_Email__c)) {
                throw new AuraHandledException('No email change requested.');
            }
            if (con.Verification_Code_Expiry__c < Datetime.now()) {
                throw new AuraHandledException('Code expired. Please request a new one.');
            }
            if (con.Verification_Code__c != '123456') {
                throw new AuraHandledException('Invalid verification code.');
            }
            
            String newEmail = con.Pending_Email__c;
            
            // Contact (non-setup) — synchrone
            con.Email                       = newEmail;
            con.Pending_Email__c            = null;
            con.Verification_Code__c        = null;
            con.Verification_Code_Expiry__c = null;
            update con;
            
            // User (setup) — @future
            // updateUserEmailAsync(userId, newEmail);
            System.enqueueJob(new CkUpdateUserEmailJob(userId, newEmail));
            
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    
    // ── 5. Changer le mot de passe ────────────────────────────
    @AuraEnabled
    public static void updatePassword(String oldPassword, String newPassword) {
        try {
            String userId   = System.UserInfo.getUserId();
            String username = System.UserInfo.getUserName();
            
            ApexPages.PageReference pageRef = Site.login(
                username, oldPassword, '/'
                );
            if (pageRef == null) {
                throw new AuraHandledException('Current password is incorrect.');
            }
            
            System.setPassword(userId, newPassword);
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ── Helpers ───────────────────────────────────────────────
    private static String generateCode() {
        Integer code = Math.round(Math.random() * 900000) + 100000;
        return String.valueOf(code);
    }
    
    private static void sendVerificationEmail(String email, String code) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ email });
            mail.setSubject('TalFlow Express — Verify Your New Email');
            mail.setSaveAsActivity(false);
            
            List<OrgWideEmailAddress> owea = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = 'Hasnaoui Yassine' LIMIT 1
            ];
            if (!owea.isEmpty()) mail.setOrgWideEmailAddressId(owea[0].Id);
            
            String htmlBody =
                '<html><body style="font-family:Arial,sans-serif;'
                + 'background:#f4f4f4;padding:30px 0;">'
                + '<table width="600" align="center"'
                + ' style="background:#fff;border-radius:12px;overflow:hidden;">'
                + '<tr><td style="background:#0A1628;padding:28px;text-align:center;">'
                + '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">TalFlow Express</h1>'
                + '</td></tr>'
                + '<tr><td style="padding:32px 36px;">'
                + '<p style="color:#0A1628;font-size:15px;">Email Verification</p>'
                + '<p style="color:#495057;font-size:14px;line-height:1.7;">'
                + 'Your verification code for your new email address is:</p>'
                + '<div style="background:#F8F9FA;border-radius:12px;padding:20px;'
                + 'text-align:center;margin:20px 0;">'
                + '<span style="font-size:32px;font-weight:800;'
                + 'letter-spacing:8px;color:#FF6B1A;">' + code + '</span>'
                + '</div>'
                + '<p style="color:#868E96;font-size:13px;">'
                + 'This code expires in 30 minutes.</p>'
                + '</td></tr></table></body></html>';
            
            mail.setHtmlBody(htmlBody);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Email failed: ' + e.getMessage());
        }
    }
    
    // ── Wrappers ──────────────────────────────────────────────
    public class ProfileData {
        @AuraEnabled public String  firstName;
        @AuraEnabled public String  lastName;
        @AuraEnabled public String  email;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  city;
        @AuraEnabled public String  country;
        @AuraEnabled public String  contactId;
        @AuraEnabled public String  photoUrl;
        @AuraEnabled public Boolean isSocialUser;
    }
}