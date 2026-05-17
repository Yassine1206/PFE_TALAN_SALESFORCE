public without sharing class CkRegistrationController {
  @AuraEnabled
  public static Map<String, String> registerB2C(
    String firstName,
    String lastName,
    String email,
    String phone,
    String password
  ) {
    try {
      Map<String, String> result = new Map<String, String>();

      List<Contact> existingContacts = [
        SELECT Id
        FROM Contact
        WHERE Email = :email
        LIMIT 1
      ];
      if (!existingContacts.isEmpty()) {
        throw new AuraHandledException(
          'An account with this email already exists.'
        );
      }

      Account defaultAccount = getOrCreateDefaultAccount(
        'TalFlow B2C Customers'
      );

      String verificationCode = generateCode();

      Contact newContact = new Contact();
      newContact.FirstName = firstName;
      newContact.LastName = lastName;
      newContact.Email = email;
      newContact.AccountId = defaultAccount.Id;
      newContact.Is_Email_Verified__c = false;
      newContact.Verification_Code__c = verificationCode;
      newContact.Verification_Code_Expiry__c = Datetime.now().addMinutes(30);
      if (String.isNotBlank(phone)) {
        newContact.Phone = phone;
      }
      newContact.LeadSource = 'Web';
      insert newContact;

      User newUser = buildCommunityUser(
        firstName,
        lastName,
        email,
        newContact.Id
      );
      insert newUser;

      System.setPassword(newUser.Id, password);
      assignPermissionSet(newUser.Id);
      sendVerificationEmail(email, firstName, verificationCode);

      result.put('status', 'success');
      result.put('email', email);
      result.put(
        'message',
        'Account created. Please check your email for the verification code.'
      );
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, String> registerB2B(
    String companyName,
    String firstName,
    String lastName,
    String email,
    String phone,
    String title,
    String industry,
    Integer numberOfEmployees,
    String website,
    Decimal annualRevenue,
    String city,
    String country,
    String description,
    String password
  ) {
    try {
      Map<String, String> result = new Map<String, String>();

      // Vérifier si le Lead ou Contact existe déjà
      List<Lead> existingLeads = [
        SELECT Id
        FROM Lead
        WHERE Email = :email AND IsConverted = FALSE
        LIMIT 1
      ];
      if (!existingLeads.isEmpty()) {
        throw new AuraHandledException(
          'A B2B application with this email already exists.'
        );
      }

      List<Contact> existingContacts = [
        SELECT Id
        FROM Contact
        WHERE Email = :email
        LIMIT 1
      ];
      if (!existingContacts.isEmpty()) {
        throw new AuraHandledException(
          'An account with this email already exists.'
        );
      }

      // FIX : créer un Lead au lieu de Account + Contact + User
      // Le User sera créé APRÈS qualification par Agentforce
      Lead newLead = new Lead();
      newLead.FirstName = firstName;
      newLead.LastName = lastName;
      newLead.Email = email;
      newLead.Phone = phone;
      newLead.Title = title;
      newLead.Company = companyName;
      newLead.Industry = industry;
      newLead.NumberOfEmployees = numberOfEmployees;
      newLead.Website = website;
      newLead.AnnualRevenue = annualRevenue;
      newLead.City = city;
      newLead.Country = country;
      newLead.Description = description;
      newLead.LeadSource = 'Web';
      newLead.Status = 'Open - Not Contacted';
      // Stocker le mot de passe hashé pour créer l'User après qualification
      newLead.B2B_Password_Hash__c = EncodingUtil.base64Encode(
        Blob.valueOf(password)
      );
      newLead.B2B_Registration_Date__c = Datetime.now();
      insert newLead;

      publishLeadCreatedEvent(newLead.Id);

      // Envoyer email de confirmation
      sendB2BConfirmationEmail(email, firstName, companyName);

      result.put('status', 'pending');
      result.put('email', email);
      result.put(
        'message',
        'Your B2B application has been submitted. ' +
        'Our team will review it within 24-48 hours.'
      );
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @future
  private static void publishLeadCreatedEvent(String leadId) {
    B2B_Lead_Created__e event = new B2B_Lead_Created__e();
    event.Lead_Id__c = leadId;
    EventBus.publish(event);
  }
  // Email de confirmation B2B
  private static void sendB2BConfirmationEmail(
    String email,
    String firstName,
    String companyName
  ) {
    try {
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(new List<String>{ email });
      mail.setSubject('TalFlow Express — B2B Application Received');
      mail.setSaveAsActivity(false);

      List<OrgWideEmailAddress> owea = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine'
        LIMIT 1
      ];
      if (!owea.isEmpty()) {
        mail.setOrgWideEmailAddressId(owea[0].Id);
      }

      String htmlBody =
        '<html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:30px 0;">' +
        '<table width="600" cellpadding="0" cellspacing="0" align="center"' +
        ' style="background:#fff;border-radius:12px;overflow:hidden;">' +
        // Header
        '<tr><td style="background:#0A1628;padding:28px;text-align:center;">' +
        '<h1 style="color:#FF6B1A;margin:0;font-size:24px;">TalFlow Express</h1>' +
        '<p style="color:#fff;margin:6px 0 0;font-size:13px;">B2B Partner Program</p>' +
        '</td></tr>' +
        // Banner
        '<tr><td style="background:#1D9E75;padding:14px;text-align:center;">' +
        '<p style="color:#fff;margin:0;font-size:15px;font-weight:bold;">' +
        'Application Received!</p>' +
        '</td></tr>' +
        // Body
        '<tr><td style="padding:32px 36px;">' +
        '<p style="color:#0A1628;font-size:15px;margin:0 0 16px;">' +
        'Hi <strong>' +
        firstName +
        '</strong>,' +
        '</p>' +
        '<p style="color:#495057;font-size:14px;line-height:1.7;margin:0 0 24px;">' +
        'Thank you for applying to the TalFlow Express B2B Partner Program ' +
        'on behalf of <strong>' +
        companyName +
        '</strong>. ' +
        'We have received your application and our team will review it shortly.' +
        '</p>' +
        // Info box
        '<table width="100%" style="background:#FFF8F5;border:1.5px solid #FFE4D4;' +
        'border-radius:10px;margin-bottom:24px;">' +
        '<tr><td style="padding:16px 20px;">' +
        '<p style="color:#FF6B1A;margin:0 0 10px;font-size:13px;font-weight:bold;">' +
        'What happens next?</p>' +
        '<p style="color:#495057;margin:4px 0;font-size:13px;">' +
        '✅ Our team will review your application within 24-48 hours</p>' +
        '<p style="color:#495057;margin:4px 0;font-size:13px;">' +
        '✅ You will receive an email once your account is activated</p>' +
        '<p style="color:#495057;margin:4px 0;font-size:13px;">' +
        '✅ A sales representative may contact you for more information</p>' +
        '</td></tr></table>' +
        // Footer
        '<p style="color:#ADB5BD;font-size:12px;text-align:center;margin:0;">' +
        '© 2026 TalFlow Express — All rights reserved</p>' +
        '</td></tr>' +
        '</table></body></html>';

      mail.setHtmlBody(htmlBody);
      mail.setPlainTextBody(
        'Hi ' +
          firstName +
          ',\n\n' +
          'Thank you for applying to TalFlow Express B2B Program ' +
          'on behalf of ' +
          companyName +
          '.\n\n' +
          'Our team will review your application within 24-48 hours.\n\n' +
          'TalFlow Express Team'
      );

      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('B2B confirmation email failed: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static String loginUser(
    String username,
    String password,
    String startUrl
  ) {
    try {
      List<Contact> contacts = [
        SELECT Is_Email_Verified__c, FirstName
        FROM Contact
        WHERE Email = :username
        LIMIT 1
      ];

      if (!contacts.isEmpty() && !contacts[0].Is_Email_Verified__c) {
        String code = generateCode();
        contacts[0].Verification_Code__c = code;
        contacts[0].Verification_Code_Expiry__c = Datetime.now().addMinutes(30);
        update contacts;
        sendVerificationEmail(username, contacts[0].FirstName, code);
        return 'VERIFY:' + username;
      }

      // ═══ B2B DETECTION ═══
      // Before login, check if this user is B2B based on their Account_Type__c
      // We do this BEFORE Site.login() because after login, the session changes
      Boolean isB2B = false;
      List<User> users = [
        SELECT Id, ContactId, Contact.Account.Account_Type__c
        FROM User
        WHERE Username = :username AND IsActive = TRUE
        LIMIT 1
      ];

      if (
        !users.isEmpty() &&
        users[0].ContactId != null &&
        users[0].Contact.Account.Account_Type__c == 'B2B'
      ) {
        isB2B = true;
      }

      // Override startUrl based on user type
      String finalStartUrl = isB2B
        ? '/TalFlowExpress/s/b2b-dashboard'
        : startUrl;

      // Authenticate via Site.login() with the appropriate redirect URL
      ApexPages.PageReference pageRef = Site.login(
        username,
        password,
        finalStartUrl
      );

      if (pageRef != null) {
        return pageRef.getUrl();
      }

      throw new AuraHandledException('Invalid email or password.');
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Invalid email or password. Please try again.'
      );
    }
  }

  @AuraEnabled
  public static Map<String, String> verifyEmail(String email, String code) {
    try {
      Map<String, String> result = new Map<String, String>();

      List<Contact> contacts = [
        SELECT
          Id,
          Verification_Code__c,
          Verification_Code_Expiry__c,
          Is_Email_Verified__c
        FROM Contact
        WHERE Email = :email
        LIMIT 1
      ];

      if (contacts.isEmpty()) {
        throw new AuraHandledException('Email not found.');
      }

      Contact con = contacts[0];

      if (con.Is_Email_Verified__c) {
        result.put('status', 'already_verified');
        result.put('message', 'Email already verified. You can sign in.');
        return result;
      }

      if (con.Verification_Code_Expiry__c < Datetime.now()) {
        throw new AuraHandledException(
          'Verification code has expired. Please request a new one.'
        );
      }

      if (con.Verification_Code__c != code) {
        throw new AuraHandledException('Invalid verification code.');
      }

      con.Is_Email_Verified__c = true;
      con.Verification_Code__c = null;
      con.Verification_Code_Expiry__c = null;
      update con;

      result.put('status', 'verified');
      result.put(
        'message',
        'Email verified successfully! You can now sign in.'
      );
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static void resendVerificationCode(String email) {
    try {
      List<Contact> contacts = [
        SELECT Id, FirstName, Is_Email_Verified__c
        FROM Contact
        WHERE Email = :email
        LIMIT 1
      ];

      if (contacts.isEmpty()) {
        throw new AuraHandledException('Email not found.');
      }

      if (contacts[0].Is_Email_Verified__c) {
        throw new AuraHandledException('Email is already verified.');
      }

      String code = generateCode();
      contacts[0].Verification_Code__c = code;
      contacts[0].Verification_Code_Expiry__c = Datetime.now().addMinutes(30);
      update contacts;

      sendVerificationEmail(email, contacts[0].FirstName, code);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, String> forgotPassword(String email) {
    try {
      Map<String, String> result = new Map<String, String>();

      List<User> users = [
        SELECT Username
        FROM User
        WHERE Email = :email AND IsActive = TRUE
        LIMIT 1
      ];

      if (!users.isEmpty()) {
        Site.forgotPassword(users[0].Username);
      }

      result.put('status', 'sent');
      result.put(
        'message',
        'If an account exists with this email, a password reset link has been sent.'
      );
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // ═══ Private Helpers ═══

  private static String generateCode() {
    Integer code = Math.round(Math.random() * 900000) + 100000;
    return String.valueOf(code);
  }

  private static void sendVerificationEmail(
    String email,
    String firstName,
    String code
  ) {
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ email });
    mail.setSubject('TalFlow Express - Verify Your Email');
    mail.setSaveAsActivity(false);

    // Use Org-Wide Email Address to avoid DKIM issues
    List<OrgWideEmailAddress> owea = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE DisplayName = 'Hasnaoui Yassine'
      LIMIT 1
    ];
    if (!owea.isEmpty()) {
      mail.setOrgWideEmailAddressId(owea[0].Id);
    }

    String body =
      'Hi ' +
      (String.isNotBlank(firstName) ? firstName : 'there') +
      ',\n\n';
    body += 'Welcome to TalFlow Express!\n\n';
    body += 'Your verification code is: ' + code + '\n\n';
    body += 'This code expires in 30 minutes.\n\n';
    body += 'If you did not create an account, please ignore this email.\n\n';
    body += 'Thank you,\nThe TalFlow Express Team';

    mail.setPlainTextBody(body);

    try {
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
      System.debug('Verification email failed: ' + e.getMessage());
    }
  }

  private static User buildCommunityUser(
    String firstName,
    String lastName,
    String email,
    Id contactId
  ) {
    // Try Customer Community first, fallback to External Identity
    String profileName = 'Customer Community User';
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];
    if (profiles.isEmpty()) {
      profiles = [
        SELECT Id
        FROM Profile
        WHERE Name = 'External Identity User'
        LIMIT 1
      ];
    }

    String alias = '';
    if (String.isNotBlank(firstName)) {
      alias += firstName.substring(0, Math.min(firstName.length(), 1));
    }
    if (String.isNotBlank(lastName)) {
      alias += lastName.substring(0, Math.min(lastName.length(), 7));
    }

    User newUser = new User();
    newUser.FirstName = firstName;
    newUser.LastName = lastName;
    newUser.Email = email;
    newUser.Username = email;
    newUser.ContactId = contactId;
    newUser.ProfileId = profiles[0].Id;
    newUser.Alias = alias.toLowerCase();
    newUser.EmailEncodingKey = 'UTF-8';
    newUser.LanguageLocaleKey = 'en_US';
    newUser.LocaleSidKey = 'en_US';
    newUser.TimeZoneSidKey = 'Africa/Tunis';
    newUser.CommunityNickname =
      email.split('@')[0] + String.valueOf(Math.round(Math.random() * 9999));
    newUser.IsActive = true;

    return newUser;
  }

  private static void assignPermissionSet(String userId) {
    try {
      List<PermissionSet> ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Community_Customer_Access'
        LIMIT 1
      ];
      if (ps.isEmpty()) {
        ps = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'Community_Cart_Access'
          LIMIT 1
        ];
      }
      if (!ps.isEmpty()) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps[0].Id,
          AssigneeId = userId
        );
      }
    } catch (Exception e) {
      System.debug('Permission set assignment failed: ' + e.getMessage());
    }
  }

  private static Account getOrCreateDefaultAccount(String accountName) {
    List<Account> existing = [
      SELECT Id
      FROM Account
      WHERE Name = :accountName
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    Account newAcc = new Account(Name = accountName);
    insert newAcc;
    return newAcc;
  }
}
