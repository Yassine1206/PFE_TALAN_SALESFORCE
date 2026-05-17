@isTest
private class CkLoginRedirectControllerTest {
  private static User createCommunityUser(String accountType, String suffix) {
    Account acc = new Account(
      Name = 'Test B2B Account ' + suffix,
      Account_Type__c = accountType
    );
    insert acc;

    Contact con = new Contact(
      FirstName = 'Test',
      LastName = 'User' + suffix,
      AccountId = acc.Id,
      Email = 'test' + suffix + '@talflow.test'
    );
    insert con;

    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Customer Community User'
      LIMIT 1
    ];

    User u = new User(
      Username = 'test' + suffix + System.currentTimeMillis() + '@talflow.test',
      Email = 'test' + suffix + '@talflow.test',
      FirstName = 'Test',
      LastName = 'User' + suffix,
      Alias = ('t' + suffix).left(8),
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id,
      ContactId = con.Id
    );
    insert u;

    return u;
  }

  @isTest
  static void testB2BUserGetsRedirectedToDashboard() {
    User b2bUser = createCommunityUser('B2B', 'B2B1');

    Test.startTest();
    System.runAs(b2bUser) {
      CkLoginRedirectController.UserContext ctx = CkLoginRedirectController.getUserContext();

      System.assertEquals('B2B', ctx.accountType, 'Should be B2B');
      System.assertEquals(
        'b2b-dashboard',
        ctx.redirectPage,
        'B2B user should be redirected to b2b-dashboard'
      );
      System.assertEquals(
        true,
        ctx.shouldRedirect,
        'shouldRedirect must be true'
      );
      System.assertEquals(false, ctx.isGuest, 'Should not be guest');
      System.assertEquals('Test', ctx.firstName, 'firstName should be Test');
    }
    Test.stopTest();
  }

  @isTest
  static void testB2CUserStaysOnHome() {
    User b2cUser = createCommunityUser('B2C', 'B2C1');

    Test.startTest();
    System.runAs(b2cUser) {
      CkLoginRedirectController.UserContext ctx = CkLoginRedirectController.getUserContext();

      System.assertEquals('B2C', ctx.accountType, 'Should be B2C');
      System.assertEquals(
        null,
        ctx.redirectPage,
        'B2C should have no redirect'
      );
      System.assertEquals(
        false,
        ctx.shouldRedirect,
        'shouldRedirect must be false'
      );
      System.assertEquals(false, ctx.isGuest, 'Should not be guest');
    }
    Test.stopTest();
  }

  @isTest
  static void testNullAccountTypeDefaultsToB2C() {
    User defaultUser = createCommunityUser(null, 'NULL1');

    Test.startTest();
    System.runAs(defaultUser) {
      CkLoginRedirectController.UserContext ctx = CkLoginRedirectController.getUserContext();

      System.assertEquals(
        'B2C',
        ctx.accountType,
        'Null account type should default to B2C'
      );
      System.assertEquals(
        false,
        ctx.shouldRedirect,
        'Default user should not be redirected'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testInternalUserHasNoRedirect() {
    Test.startTest();
    CkLoginRedirectController.UserContext ctx = CkLoginRedirectController.getUserContext();

    System.assertEquals('INTERNAL', ctx.accountType, 'Should be INTERNAL');
    System.assertEquals(
      false,
      ctx.shouldRedirect,
      'Internal should not redirect'
    );
    System.assertEquals(false, ctx.isGuest, 'Should not be guest');
    Test.stopTest();
  }
}
