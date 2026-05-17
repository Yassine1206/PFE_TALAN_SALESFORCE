public without sharing class CkAgentGetMyAccountInfo {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;
  }

  public class Output {
    @InvocableVariable(label='Account information')
    public String accountInfo;

    @InvocableVariable(label='Account name')
    public String accountName;

    @InvocableVariable(label='Member since (months)')
    public Integer memberSinceMonths;
  }

  @InvocableMethod(
    label='Get My Account Info'
    description='Returns the verified B2B customer account information (company, contact, location, member since)'
    category='B2B General Support'
  )
  public static List<Output> getMyAccountInfo(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactIdStr = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactIdStr);

    if (accountId == null) {
      Output out = new Output();
      out.accountInfo = 'Unable to identify your account. Please verify your identity.';
      out.accountName = 'Unknown';
      out.memberSinceMonths = 0;
      results.add(out);
      return results;
    }

    List<Account> accounts = [
      SELECT
        Id,
        Name,
        Industry,
        BillingCity,
        BillingCountry,
        CreatedDate,
        Phone,
        Website,
        Account_Type__c
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    Output out = new Output();
    if (accounts.isEmpty()) {
      out.accountInfo = 'Account not found.';
      out.accountName = 'Unknown';
      out.memberSinceMonths = 0;
    } else {
      Account acc = accounts[0];
      Integer monthsActive = Math.abs(
        Date.today().monthsBetween(acc.CreatedDate.date())
      );

      // Get contact info from contactId if provided
      String contactName = '';
      String contactEmail = '';
      if (String.isNotBlank(contactIdStr)) {
        try {
          Id cid = (Id) contactIdStr;
          Contact c = [
            SELECT FirstName, LastName, Email
            FROM Contact
            WHERE Id = :cid
            LIMIT 1
          ];
          contactName =
            (c.FirstName != null ? c.FirstName : '') +
            ' ' +
            (c.LastName != null ? c.LastName : '');
          contactEmail = c.Email != null ? c.Email : '';
        } catch (Exception e) {
          /* ignore */
        }
      }

      String info = 'Your account information:\n\n';
      if (String.isNotBlank(contactName.trim())) {
        info += '👤 Contact: ' + contactName.trim() + '\n';
      }
      if (String.isNotBlank(contactEmail)) {
        info += '📧 Email: ' + contactEmail + '\n';
      }
      info += '🏢 Company: ' + acc.Name + '\n';

      if (String.isNotBlank(acc.Industry)) {
        info += '🏭 Industry: ' + acc.Industry + '\n';
      }
      if (
        String.isNotBlank(acc.BillingCity) ||
        String.isNotBlank(acc.BillingCountry)
      ) {
        String location = '';
        if (String.isNotBlank(acc.BillingCity))
          location += acc.BillingCity;
        if (String.isNotBlank(acc.BillingCountry)) {
          if (String.isNotBlank(location))
            location += ', ';
          location += acc.BillingCountry;
        }
        info += '📍 Location: ' + location + '\n';
      }
      if (String.isNotBlank(acc.Phone)) {
        info += '📞 Phone: ' + acc.Phone + '\n';
      }
      if (String.isNotBlank(acc.Website)) {
        info += '🌐 Website: ' + acc.Website + '\n';
      }
      info +=
        '📅 Member since: ' +
        monthsActive +
        ' month' +
        (monthsActive != 1 ? 's' : '') +
        '\n';
      info +=
        '🏷️ Account type: ' +
        (acc.Account_Type__c != null ? acc.Account_Type__c : 'B2B') +
        '\n';

      out.accountInfo = info;
      out.accountName = acc.Name;
      out.memberSinceMonths = monthsActive;
    }
    results.add(out);
    return results;
  }

  private static Id resolveAccountId(String contactIdStr) {
    Id contactId = null;
    if (String.isNotBlank(contactIdStr)) {
      try {
        contactId = (Id) contactIdStr;
      } catch (Exception e) {
        System.debug('Invalid contactId string: ' + contactIdStr);
      }
    }
    if (contactId != null) {
      try {
        Contact c = [
          SELECT Id, AccountId
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        return c.AccountId;
      } catch (Exception e) {
        System.debug('Contact lookup failed: ' + e.getMessage());
      }
    }
    return null;
  }
}
