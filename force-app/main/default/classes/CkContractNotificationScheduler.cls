public without sharing class CkContractNotificationScheduler implements Schedulable {
  public void execute(SchedulableContext ctx) {
    runNotifications();
  }

  public static void runNotifications() {
    Date today = Date.today();
    Date in30Days = today.addDays(30);

    // Find contracts expiring soon that haven't been notified recently
    List<Contract> expiringContracts = [
      SELECT Id, ContractNumber, EndDate, AccountId, Account.Name
      FROM Contract
      WHERE
        Status = 'Activated'
        AND EndDate >= :today
        AND EndDate <= :in30Days
        AND AccountId != NULL
    ];

    if (expiringContracts.isEmpty())
      return;

    // Get account IDs to find Users
    Set<Id> accountIds = new Set<Id>();
    for (Contract c : expiringContracts) {
      accountIds.add(c.AccountId);
    }

    Map<Id, User> userByAccount = new Map<Id, User>();
    for (User u : [
      SELECT Id, AccountId
      FROM User
      WHERE AccountId IN :accountIds AND IsActive = TRUE
    ]) {
      userByAccount.put(u.AccountId, u);
    }

    // Find notifications created today to avoid duplicates
    DateTime startToday = DateTime.newInstance(
      today,
      Time.newInstance(0, 0, 0, 0)
    );
    Set<String> alreadyNotifiedToday = new Set<String>();
    for (Notification__c existing : [
      SELECT Title__c, User_Id__c
      FROM Notification__c
      WHERE CreatedDate >= :startToday AND Title__c LIKE 'Contract Expiring%'
    ]) {
      alreadyNotifiedToday.add(existing.User_Id__c + '|' + existing.Title__c);
    }

    List<Notification__c> toInsert = new List<Notification__c>();

    for (Contract c : expiringContracts) {
      User u = userByAccount.get(c.AccountId);
      if (u == null)
        continue;

      Integer daysLeft = today.daysBetween(c.EndDate);

      // Only notify on specific milestones (30, 14, 7, 1 days)
      if (daysLeft != 30 && daysLeft != 14 && daysLeft != 7 && daysLeft != 1)
        continue;

      String title;
      String type;
      String emoji;

      if (daysLeft == 1) {
        title = 'Contract Expiring Tomorrow';
        type = 'Alert';
        emoji = '🚨';
      } else if (daysLeft == 7) {
        title = 'Contract Expiring in 7 Days';
        type = 'Alert';
        emoji = '⚠️';
      } else if (daysLeft == 14) {
        title = 'Contract Expiring in 14 Days';
        type = 'Warning';
        emoji = '⚠️';
      } else {
        title = 'Contract Expiring in 30 Days';
        type = 'Warning';
        emoji = '📅';
      }

      // Skip if already notified today
      if (alreadyNotifiedToday.contains(u.Id + '|' + title))
        continue;

      Notification__c n = new Notification__c();
      n.User_Id__c = u.Id;
      n.Title__c = title;
      n.Message__c =
        emoji +
        ' Contract C-' +
        c.ContractNumber +
        ' expires on ' +
        c.EndDate.format() +
        '. ' +
        'Contact your account manager to renew.';
      n.Type__c = type;
      n.Action_URL__c = '/TalFlowExpress/s/my-contracts';
      n.Is_Read__c = false;

      toInsert.add(n);
    }

    if (!toInsert.isEmpty()) {
      try {
        insert toInsert;
        System.debug(
          '✅ Created ' + toInsert.size() + ' contract notifications'
        );
      } catch (Exception e) {
        System.debug('❌ Failed to insert: ' + e.getMessage());
      }
    }
  }

  /**
   * @description Schedule this job to run daily at 8:00 AM.
   * Call this from Anonymous Apex to schedule.
   */
  public static String scheduleDaily() {
    String cronExp = '0 0 8 * * ?'; // Every day at 8 AM
    return System.schedule(
      'TalFlow Contract Notification - Daily',
      cronExp,
      new CkContractNotificationScheduler()
    );
  }
}
