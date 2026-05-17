public without sharing class CkLoginRedirectController {
  public class UserContext {
    @AuraEnabled
    public String accountType { get; set; }
    @AuraEnabled
    public String redirectPage { get; set; }
    @AuraEnabled
    public String userName { get; set; }
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public Boolean isGuest { get; set; }
    @AuraEnabled
    public Boolean shouldRedirect { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static UserContext getUserContext() {
    UserContext ctx = new UserContext();
    ctx.shouldRedirect = false;

    // Case 1: Guest user (not authenticated)
    if (UserInfo.getUserType() == 'Guest') {
      ctx.isGuest = true;
      ctx.accountType = 'GUEST';
      ctx.userName = 'Guest';
      ctx.firstName = 'Guest';
      return ctx;
    }

    // Case 2: Authenticated user — load Contact + Account
    List<User> users = [
      SELECT
        Id,
        Name,
        FirstName,
        ContactId,
        Contact.AccountId,
        Contact.Account.Account_Type__c
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    ctx.isGuest = false;

    if (users.isEmpty()) {
      ctx.accountType = 'INTERNAL';
      ctx.userName = 'User';
      ctx.firstName = 'User';
      return ctx;
    }

    User u = users[0];
    ctx.userName = u.Name;
    ctx.firstName = String.isBlank(u.FirstName) ? 'User' : u.FirstName;

    // Case 3: Internal user (no Contact)
    if (u.ContactId == null) {
      ctx.accountType = 'INTERNAL';
      return ctx;
    }

    // Case 4: Community user — check Account_Type__c
    String accountType = u.Contact.Account.Account_Type__c;

    if (accountType == 'B2B') {
      ctx.accountType = 'B2B';
      ctx.redirectPage = 'b2b-dashboard';
      ctx.shouldRedirect = true;
    } else {
      // null or 'B2C' → stay on home (no redirect)
      ctx.accountType = 'B2C';
      ctx.shouldRedirect = false;
    }

    return ctx;
  }
}
