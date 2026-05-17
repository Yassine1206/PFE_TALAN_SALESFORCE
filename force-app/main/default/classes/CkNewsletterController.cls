public without sharing class CkNewsletterController {
  @AuraEnabled
  public static String subscribe(String email) {
    if (String.isBlank(email)) {
      throw new AuraHandledException('Email is required.');
    }

    // Validation email simple
    Pattern emailPattern = Pattern.compile(
      '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    );
    if (!emailPattern.matcher(email).matches()) {
      throw new AuraHandledException('Please enter a valid email address.');
    }

    // V\u00e9rifier si d\u00e9j\u00e0 inscrit
    List<Newsletter_Subscriber__c> existing = [
      SELECT Id, Is_Active__c
      FROM Newsletter_Subscriber__c
      WHERE Email__c = :email
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      // R\u00e9activation si d\u00e9sinscrit auparavant
      if (!existing[0].Is_Active__c) {
        existing[0].Is_Active__c = true;
        update existing[0];
        return 'Welcome back! You\'re subscribed again.';
      }
      return 'You\'re already subscribed. Thanks!';
    }

    try {
      Newsletter_Subscriber__c sub = new Newsletter_Subscriber__c(
        Email__c = email,
        Source__c = 'Footer',
        Subscribed_Date__c = System.now(),
        Is_Active__c = true
      );
      insert sub;
      return 'Thanks for subscribing!';
    } catch (DmlException e) {
      throw new AuraHandledException('Subscription failed. Please try again.');
    }
  }
}
