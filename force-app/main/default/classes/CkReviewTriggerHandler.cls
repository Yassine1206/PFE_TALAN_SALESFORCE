/**
 * @description Handler for Review__c trigger.
 * Recalculates Average_Rating__c, Review_Count__c, and Recommended_Percent__c
 * on Product2 when reviews are Approved/Rejected/Created/Deleted.
 */
public without sharing class CkReviewTriggerHandler {
  /**
   * @description Recalculate Product2 rollup fields based on affected reviews.
   */
  public static void recalculateProductRatings(Set<Id> productIds) {
    if (productIds == null || productIds.isEmpty())
      return;

    // Remove nulls
    productIds.remove(null);
    if (productIds.isEmpty())
      return;

    // Get all approved reviews for these products
    List<AggregateResult> ratings = [
      SELECT
        Product__c productId,
        AVG(Rating__c) avgRating,
        COUNT(Id) reviewCount
      FROM Review__c
      WHERE
        Product__c IN :productIds
        AND Type__c = 'Product'
        AND Status__c = 'Approved'
      GROUP BY Product__c
    ];

    // Get recommended counts separately
    List<AggregateResult> recommended = [
      SELECT Product__c productId, COUNT(Id) recCount
      FROM Review__c
      WHERE
        Product__c IN :productIds
        AND Type__c = 'Product'
        AND Status__c = 'Approved'
        AND Recommended__c = 'Yes'
      GROUP BY Product__c
    ];

    // Build maps
    Map<Id, Decimal> avgMap = new Map<Id, Decimal>();
    Map<Id, Integer> countMap = new Map<Id, Integer>();
    Map<Id, Integer> recMap = new Map<Id, Integer>();

    for (AggregateResult ar : ratings) {
      Id pid = (Id) ar.get('productId');
      avgMap.put(pid, (Decimal) ar.get('avgRating'));
      countMap.put(pid, (Integer) ar.get('reviewCount'));
    }

    for (AggregateResult ar : recommended) {
      Id pid = (Id) ar.get('productId');
      recMap.put(pid, (Integer) ar.get('recCount'));
    }

    // Update products
    List<Product2> toUpdate = new List<Product2>();
    for (Id pid : productIds) {
      Decimal avgRating = avgMap.containsKey(pid) ? avgMap.get(pid) : null;
      Integer count = countMap.containsKey(pid) ? countMap.get(pid) : 0;
      Integer recCount = recMap.containsKey(pid) ? recMap.get(pid) : 0;

      Decimal recPercent = (count > 0)
        ? ((Decimal) recCount / count * 100).setScale(0)
        : null;

      Product2 p = new Product2(Id = pid);
      p.Average_Rating__c = (avgRating != null) ? avgRating.setScale(1) : null;
      p.Review_Count__c = count;
      p.Recommended_Percent__c = recPercent;
      toUpdate.add(p);
    }

    if (!toUpdate.isEmpty()) {
      try {
        update toUpdate;
        System.debug('✅ Updated ratings for ' + toUpdate.size() + ' products');
      } catch (Exception e) {
        System.debug('❌ Failed to update product ratings: ' + e.getMessage());
      }
    }
  }

  /**
   * @description Handle after insert.
   */
  public static void handleAfterInsert(List<Review__c> newReviews) {
    Set<Id> productIds = new Set<Id>();
    Set<Id> reviewIds = new Set<Id>();

    for (Review__c r : newReviews) {
      if (r.Type__c == 'Product' && r.Product__c != null) {
        productIds.add(r.Product__c);
      }
      reviewIds.add(r.Id);
    }

    if (!productIds.isEmpty()) {
      recalculateProductRatings(productIds);
    }

    // Notify Sales Manager for pending reviews
    notifyPendingReviews(reviewIds);
  }

  /**
   * @description Handle after update.
   */
  public static void handleAfterUpdate(
    List<Review__c> newReviews,
    Map<Id, Review__c> oldMap
  ) {
    Set<Id> productIds = new Set<Id>();

    for (Review__c r : newReviews) {
      Review__c old = oldMap.get(r.Id);

      // Recalculate if Status changed (Pending → Approved, etc.)
      // Or Recommended changed
      // Or Rating changed (correction)
      if (
        r.Status__c != old.Status__c ||
        r.Recommended__c != old.Recommended__c ||
        r.Rating__c != old.Rating__c
      ) {
        if (r.Type__c == 'Product' && r.Product__c != null) {
          productIds.add(r.Product__c);
        }
      }
    }

    if (!productIds.isEmpty()) {
      recalculateProductRatings(productIds);
    }
  }

  /**
   * @description Handle after delete.
   */
  public static void handleAfterDelete(List<Review__c> oldReviews) {
    Set<Id> productIds = new Set<Id>();

    for (Review__c r : oldReviews) {
      if (r.Type__c == 'Product' && r.Product__c != null) {
        productIds.add(r.Product__c);
      }
    }

    if (!productIds.isEmpty()) {
      recalculateProductRatings(productIds);
    }
  }

  /**
   * @description Send notification to Sales Manager when new reviews are submitted (Pending).
   */
  private static void notifyPendingReviews(Set<Id> reviewIds) {
    if (reviewIds == null || reviewIds.isEmpty())
      return;

    List<Review__c> reviews = [
      SELECT
        Id,
        Name,
        Type__c,
        Rating__c,
        Title__c,
        Customer__r.Name,
        Product__r.Name,
        Customer_Type__c
      FROM Review__c
      WHERE Id IN :reviewIds AND Status__c = 'Pending'
    ];

    if (reviews.isEmpty())
      return;

    Set<Id> salesTeam = CkInternalNotificationService.getSalesTeamUserIds();
    if (salesTeam.isEmpty())
      return;

    for (Review__c r : reviews) {
      String subject;
      String body;

      if (r.Type__c == 'Product') {
        subject = '💬 New Product Review — ' + r.Rating__c.intValue() + '⭐';
        body =
          (r.Customer__r != null ? r.Customer__r.Name : 'Customer') +
          ' reviewed "' +
          (r.Product__r != null ? r.Product__r.Name : 'product') +
          '". Awaiting moderation.';
      } else {
        subject = '💬 New Site Review — ' + r.Rating__c.intValue() + '⭐';
        body =
          (r.Customer__r != null ? r.Customer__r.Name : 'Customer') +
          ' (' +
          r.Customer_Type__c +
          ') left a site review. Awaiting moderation.';
      }

      CkInternalNotificationService.send(
        CkInternalNotificationService.TYPE_QUOTE_ACTIVITY, // Reuse existing type, or create TYPE_REVIEW
        subject,
        body,
        salesTeam,
        r.Id
      );
    }
  }
}
