@isTest
private class CkQuoteExpirationSchedulerTest {
  // ═══════════════════════════════════════════════════════════
  // SETUP
  // ═══════════════════════════════════════════════════════════

  @TestSetup
  static void setupTestData() {
    // Create B2B Account
    Account acc = new Account(
      Name = 'Expiration Test Corp',
      Account_Type__c = 'B2B'
    );
    insert acc;

    // Create Contact
    Contact con = new Contact(
      FirstName = 'Expiry',
      LastName = 'Tester',
      Email = 'expirytest@talflow.test',
      AccountId = acc.Id,
      Is_Email_Verified__c = true
    );
    insert con;

    // Create Opportunity
    Opportunity opp = new Opportunity(
      Name = 'Expiration Test Opp',
      AccountId = acc.Id,
      StageName = 'Quoting',
      CloseDate = Date.today().addDays(30)
    );
    insert opp;

    Id pbId = Test.getStandardPricebookId();

    // Create 3 Quotes :
    //   - 1 expired (should be processed)
    //   - 1 valid (should NOT be processed)
    //   - 1 already Expired (should NOT be re-processed)
    List<Quote> quotes = new List<Quote>{
      // Past expiration date + Sent → MUST be processed
      new Quote(
        Name = 'Expired Quote A',
        OpportunityId = opp.Id,
        ContactId = con.Id,
        B2B_Status__c = 'Sent to Customer',
        Status = 'Presented',
        ExpirationDate = Date.today().addDays(-5),
        Pricebook2Id = pbId
      ),
      // Future expiration date + Sent → MUST be ignored
      new Quote(
        Name = 'Valid Quote B',
        OpportunityId = opp.Id,
        ContactId = con.Id,
        B2B_Status__c = 'Sent to Customer',
        Status = 'Presented',
        ExpirationDate = Date.today().addDays(15),
        Pricebook2Id = pbId
      ),
      // Past expiration date but already Expired → MUST be ignored
      new Quote(
        Name = 'Already Expired Quote C',
        OpportunityId = opp.Id,
        ContactId = con.Id,
        B2B_Status__c = 'Expired',
        Status = 'Denied',
        ExpirationDate = Date.today().addDays(-10),
        Pricebook2Id = pbId
      )
    };
    insert quotes;
  }

  // ═══════════════════════════════════════════════════════════
  // TESTS
  // ═══════════════════════════════════════════════════════════

  @isTest
  static void testBatchExpiresOnlyEligibleQuotes() {
    // Verify initial state
    Integer sentBefore = [
      SELECT COUNT()
      FROM Quote
      WHERE B2B_Status__c = 'Sent to Customer' AND ExpirationDate < TODAY
    ];
    System.assertEquals(
      1,
      sentBefore,
      'Setup should have exactly 1 expired-but-still-Sent quote'
    );

    Test.startTest();
    Database.executeBatch(new CkQuoteExpirationScheduler(), 50);
    Test.stopTest();

    // After batch: the expired quote should be 'Expired'
    Integer expiredAfter = [
      SELECT COUNT()
      FROM Quote
      WHERE Name = 'Expired Quote A' AND B2B_Status__c = 'Expired'
    ];
    System.assertEquals(
      1,
      expiredAfter,
      'Expired Quote A should now be marked as Expired'
    );

    // Valid quote should remain unchanged
    Quote validQuote = [
      SELECT B2B_Status__c
      FROM Quote
      WHERE Name = 'Valid Quote B'
      LIMIT 1
    ];
    System.assertEquals(
      'Sent to Customer',
      validQuote.B2B_Status__c,
      'Valid Quote B should still be Sent to Customer'
    );

    // Already-Expired quote should remain unchanged (not re-processed)
    Quote alreadyExpired = [
      SELECT B2B_Status__c
      FROM Quote
      WHERE Name = 'Already Expired Quote C'
      LIMIT 1
    ];
    System.assertEquals('Expired', alreadyExpired.B2B_Status__c);
  }

  @isTest
  static void testSchedulableExecutesBatch() {
    Test.startTest();
    // Schedule the job (CRON: midnight every day)
    String cronExp = '0 0 0 * * ?';
    String jobId = System.schedule(
      'Test_CkQuoteExpirationScheduler',
      cronExp,
      new CkQuoteExpirationScheduler()
    );
    Test.stopTest();

    // Verify the job was scheduled
    CronTrigger ct = [
      SELECT Id, CronExpression, NextFireTime, State
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    System.assertEquals(cronExp, ct.CronExpression);
  }

  @isTest
  static void testBatchHandlesEmptyScope() {
    // Delete the expired quote so the batch finds nothing
    delete [SELECT Id FROM Quote WHERE Name = 'Expired Quote A'];

    Test.startTest();
    Database.executeBatch(new CkQuoteExpirationScheduler(), 50);
    Test.stopTest();

    // Should not throw — completes gracefully
    Integer remainingExpired = [
      SELECT COUNT()
      FROM Quote
      WHERE B2B_Status__c = 'Expired' AND Name = 'Expired Quote A'
    ];
    System.assertEquals(0, remainingExpired);
  }
}
