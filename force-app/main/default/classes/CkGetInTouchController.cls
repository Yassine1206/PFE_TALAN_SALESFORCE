/**
 * @description Backend for Get In Touch form.
 * Creates a Case + sends notif to Commercial Agent.
 */
public without sharing class CkGetInTouchController {
  public class ContactResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled
  public static ContactResult submitContactForm(
    String firstName,
    String lastName,
    String email,
    String phone,
    String subject,
    String message
  ) {
    ContactResult result = new ContactResult();
    result.success = false;

    try {
      // Validation
      if (String.isBlank(message)) {
        result.message = 'Please enter a message.';
        return result;
      }

      // For guest users (not logged in), require name + email
      Boolean isGuest = (UserInfo.getUserType() == 'Guest');
      if (isGuest) {
        if (
          String.isBlank(firstName) ||
          String.isBlank(lastName) ||
          String.isBlank(email)
        ) {
          result.message = 'Please fill in your name and email.';
          return result;
        }
        if (!isValidEmail(email)) {
          result.message = 'Please enter a valid email address.';
          return result;
        }
      }

      // Build Case
      Case c = new Case();
      c.Status = 'New';
      c.Origin = 'Web';
      c.Priority = 'Medium';
      c.Type = String.isNotBlank(subject) ? subject : 'General Inquiry';
      c.Subject =
        '[Get In Touch] ' +
        (String.isNotBlank(subject) ? subject : 'New Inquiry');
      c.Description = message;

      // Linking : if user logged in, link to Contact + Account
      String contactName = '';
      String contactEmail = '';

      if (!isGuest) {
        String userId = UserInfo.getUserId();
        List<User> users = [
          SELECT Id, Name, Email, Phone, ContactId, Contact.AccountId
          FROM User
          WHERE Id = :userId
          LIMIT 1
        ];
        if (!users.isEmpty()) {
          User u = users[0];
          contactName = u.Name;
          contactEmail = u.Email;
          if (u.ContactId != null)
            c.ContactId = u.ContactId;
          if (u.Contact != null && u.Contact.AccountId != null) {
            c.AccountId = u.Contact.AccountId;
          }
          c.SuppliedEmail = u.Email;
          c.SuppliedPhone = u.Phone;
          c.SuppliedName = u.Name;
        }
      } else {
        // Guest user — use form data
        contactName = firstName + ' ' + lastName;
        contactEmail = email;
        c.SuppliedName = firstName + ' ' + lastName;
        c.SuppliedEmail = email;
        c.SuppliedPhone = phone;
      }

      insert c;

      // Re-query for CaseNumber
      Case savedCase = [
        SELECT Id, CaseNumber
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      // Send notification to Commercial Agent
      try {
        Set<Id> agents = CkInternalNotificationService.getUsersByRole(
          'Commercial_Agent'
        );
        if (!agents.isEmpty()) {
          String shortMsg = message.length() > 100
            ? message.substring(0, 97) + '...'
            : message;

          CkInternalNotificationService.send(
            CkInternalNotificationService.TYPE_LIVE_CHAT,
            '📩 New Contact Request',
            'From ' + contactName + ' (' + contactEmail + '): ' + shortMsg,
            agents,
            savedCase.Id
          );
        }
      } catch (Exception e) {
        System.debug('Failed to send notif: ' + e.getMessage());
      }

      result.success = true;
      result.caseNumber = savedCase.CaseNumber;
      result.message =
        'Thank you! We received your message. Reference: ' +
        savedCase.CaseNumber;
      return result;
    } catch (Exception e) {
      result.message = 'Failed to send: ' + e.getMessage();
      return result;
    }
  }

  private static Boolean isValidEmail(String email) {
    if (String.isBlank(email))
      return false;
    return Pattern.matches(
      '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      email
    );
  }
}
