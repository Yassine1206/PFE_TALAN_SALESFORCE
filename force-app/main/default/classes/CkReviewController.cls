/**
 * @description Controller for product reviews.
 * Used by ckProductReviews and ckWriteProductReview LWCs.
 */
public without sharing class CkReviewController {
  // ═══════════════════════════════════════════════════════
  // PUBLIC WRAPPER CLASSES
  // ═══════════════════════════════════════════════════════

  public class ReviewWrapper {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer rating;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String comment;
    @AuraEnabled
    public String customerName;
    @AuraEnabled
    public String customerType; // B2C / B2B
    @AuraEnabled
    public String recommended; // Yes/No
    @AuraEnabled
    public Boolean isRecommended;
    @AuraEnabled
    public String createdDate;
    @AuraEnabled
    public String createdDateFormatted; // "Jan 15, 2026"
    @AuraEnabled
    public List<Integer> starsArray; // [1,1,1,1,0] for 4-star
  }

  public class ReviewSummary {
    @AuraEnabled
    public Decimal averageRating; // 0-5
    @AuraEnabled
    public Integer reviewCount;
    @AuraEnabled
    public Integer recommendedPercent;
    @AuraEnabled
    public List<RatingBreakdown> breakdown; // 5★: 10, 4★: 5, etc.
    @AuraEnabled
    public Boolean canWriteReview; // Did current user buy + not yet reviewed?
    @AuraEnabled
    public String cannotReviewReason; // If can't review, why
    @AuraEnabled
    public List<ReviewWrapper> reviews;
  }

  public class RatingBreakdown {
    @AuraEnabled
    public Integer stars; // 5, 4, 3, 2, 1
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public Decimal percentage; // 0-100
  }

  // ═══════════════════════════════════════════════════════
  // PUBLIC METHODS
  // ═══════════════════════════════════════════════════════

  /**
   * @description Get reviews summary for a product (rating, count, breakdown, recent reviews).
   */
  @AuraEnabled(cacheable=true)
  public static ReviewSummary getProductReviewSummary(Id productId) {
    ReviewSummary summary = new ReviewSummary();
    summary.canWriteReview = false;
    summary.reviews = new List<ReviewWrapper>();

    if (productId == null) {
      summary.cannotReviewReason = 'Invalid product';
      return summary;
    }

    // Get product rollup fields
    List<Product2> products = [
      SELECT
        Id,
        Name,
        Average_Rating__c,
        Review_Count__c,
        Recommended_Percent__c
      FROM Product2
      WHERE Id = :productId
      LIMIT 1
    ];

    if (products.isEmpty()) {
      summary.cannotReviewReason = 'Product not found';
      return summary;
    }

    Product2 p = products[0];
    summary.averageRating = p.Average_Rating__c != null
      ? p.Average_Rating__c
      : 0;
    summary.reviewCount = p.Review_Count__c != null
      ? p.Review_Count__c.intValue()
      : 0;
    summary.recommendedPercent = p.Recommended_Percent__c != null
      ? p.Recommended_Percent__c.intValue()
      : null;

    // Get approved reviews
    List<Review__c> reviews = [
      SELECT
        Id,
        Name,
        Rating__c,
        Title__c,
        Comment__c,
        Recommended__c,
        Customer_Name__c,
        Customer_Type__c,
        CreatedDate
      FROM Review__c
      WHERE
        Product__c = :productId
        AND Type__c = 'Product'
        AND Status__c = 'Approved'
      ORDER BY CreatedDate DESC
      LIMIT 20
    ];

    // Build rating breakdown (count per star)
    Map<Integer, Integer> starCounts = new Map<Integer, Integer>{
      5 => 0,
      4 => 0,
      3 => 0,
      2 => 0,
      1 => 0
    };

    for (Review__c r : reviews) {
      Integer rating = r.Rating__c.intValue();
      if (starCounts.containsKey(rating)) {
        starCounts.put(rating, starCounts.get(rating) + 1);
      }
      summary.reviews.add(buildReviewWrapper(r));
    }

    // Build breakdown
    summary.breakdown = new List<RatingBreakdown>();
    Integer total = summary.reviewCount > 0 ? summary.reviewCount : 1; // Avoid div by zero
    for (Integer star = 5; star >= 1; star--) {
      RatingBreakdown rb = new RatingBreakdown();
      rb.stars = star;
      rb.count = starCounts.get(star);
      rb.percentage = ((Decimal) rb.count / total * 100).setScale(0);
      summary.breakdown.add(rb);
    }

    // Check if current user can write a review
    checkWriteEligibility(summary, productId);

    return summary;
  }

  /**
   * @description Submit a new review.
   */
  @AuraEnabled
  public static Id submitProductReview(
    Id productId,
    Integer rating,
    String title,
    String comment,
    Boolean recommended
  ) {
    try {
      // Validation
      if (productId == null)
        throw new AuraHandledException('Product is required.');
      if (rating == null || rating < 1 || rating > 5) {
        throw new AuraHandledException('Rating must be between 1 and 5.');
      }
      if (String.isBlank(title))
        throw new AuraHandledException('Title is required.');
      if (String.isBlank(comment))
        throw new AuraHandledException('Comment is required.');

      // Check current user
      String userId = UserInfo.getUserId();
      User u = [
        SELECT Id, Name, ContactId, Contact.Name, Contact.AccountId, UserType
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null) {
        throw new AuraHandledException(
          'You must be a registered customer to write a review.'
        );
      }

      // Check eligibility (has the user bought this product?)
      EligibilityResult eligibility = checkEligibility(u.ContactId, productId);
      if (!eligibility.canReview) {
        throw new AuraHandledException(eligibility.reason);
      }

      // Determine customer type
      Boolean isB2B = (u.UserType == 'PowerCustomerSuccess' ||
      u.UserType == 'CspLitePortal' ||
      u.UserType == 'CustomerSuccess');

      // Create review
      Review__c r = new Review__c();
      r.Type__c = 'Product';
      r.Product__c = productId;
      r.Customer__c = u.ContactId;
      r.Order__c = eligibility.orderId;
      r.Rating__c = rating;
      r.Title__c = title.length() > 80 ? title.substring(0, 80) : title;
      r.Comment__c = comment.length() > 2000
        ? comment.substring(0, 2000)
        : comment;
      r.Status__c = 'Pending';
      r.Recommended__c = recommended ? 'Yes' : 'No';
      r.Customer_Name__c = u.Contact.Name;
      r.Customer_Type__c = isB2B ? 'B2B' : 'B2C';

      insert r;
      return r.Id;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Submit a site review (no product).
   */
  @AuraEnabled
  public static Id submitSiteReview(
    Integer rating,
    String title,
    String comment,
    Boolean recommended
  ) {
    try {
      // Validation
      if (rating == null || rating < 1 || rating > 5) {
        throw new AuraHandledException('Rating must be between 1 and 5.');
      }
      if (String.isBlank(title))
        throw new AuraHandledException('Title is required.');
      if (String.isBlank(comment))
        throw new AuraHandledException('Comment is required.');

      // Check current user
      String userId = UserInfo.getUserId();
      User u = [
        SELECT Id, Name, ContactId, Contact.Name, UserType
        FROM User
        WHERE Id = :userId
        LIMIT 1
      ];

      if (u.ContactId == null) {
        throw new AuraHandledException(
          'You must be a registered customer to write a review.'
        );
      }

      Boolean isB2B = (u.UserType == 'PowerCustomerSuccess' ||
      u.UserType == 'CspLitePortal' ||
      u.UserType == 'CustomerSuccess');

      Review__c r = new Review__c();
      r.Type__c = 'Site';
      r.Customer__c = u.ContactId;
      r.Rating__c = rating;
      r.Title__c = title.length() > 80 ? title.substring(0, 80) : title;
      r.Comment__c = comment.length() > 2000
        ? comment.substring(0, 2000)
        : comment;
      r.Status__c = 'Pending';
      r.Recommended__c = recommended ? 'Yes' : 'No';
      r.Customer_Name__c = u.Contact.Name;
      r.Customer_Type__c = isB2B ? 'B2B' : 'B2C';

      insert r;
      return r.Id;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Get approved site reviews (for home page B2C / dashboard B2B).
   */
  @AuraEnabled(cacheable=true)
  public static List<ReviewWrapper> getSiteReviews(Integer maxReviews) {
    Integer limitNum = (maxReviews != null && maxReviews > 0) ? maxReviews : 10;

    List<Review__c> reviews = [
      SELECT
        Id,
        Name,
        Rating__c,
        Title__c,
        Comment__c,
        Recommended__c,
        Customer_Name__c,
        Customer_Type__c,
        CreatedDate
      FROM Review__c
      WHERE Type__c = 'Site' AND Status__c = 'Approved'
      ORDER BY CreatedDate DESC
      LIMIT :limitNum
    ];

    List<ReviewWrapper> results = new List<ReviewWrapper>();
    for (Review__c r : reviews) {
      results.add(buildReviewWrapper(r));
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════

  private class EligibilityResult {
    public Boolean canReview;
    public String reason;
    public Id orderId;
  }

  private static EligibilityResult checkEligibility(
    Id contactId,
    Id productId
  ) {
    EligibilityResult result = new EligibilityResult();
    result.canReview = false;

    // Check if customer has an Order with this product (Activated or Delivered)
    List<Order> orders = [
      SELECT
        Id,
        Status,
        BillToContactId,
        (SELECT Id, Product2Id FROM OrderItems WHERE Product2Id = :productId)
      FROM Order
      WHERE
        BillToContactId = :contactId
        AND Status IN ('Activated', 'Delivered')
    ];

    Boolean hasBought = false;
    for (Order o : orders) {
      if (!o.OrderItems.isEmpty()) {
        hasBought = true;
        result.orderId = o.Id;
        break;
      }
    }

    if (!hasBought) {
      result.reason = 'You can only review products you have purchased.';
      return result;
    }

    // Check if user already submitted a review for this product
    List<Review__c> existing = [
      SELECT Id
      FROM Review__c
      WHERE
        Customer__c = :contactId
        AND Product__c = :productId
        AND Type__c = 'Product'
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      result.reason = 'You have already submitted a review for this product.';
      return result;
    }

    result.canReview = true;
    return result;
  }

  private static void checkWriteEligibility(
    ReviewSummary summary,
    Id productId
  ) {
    try {
      String userId = UserInfo.getUserId();

      // Skip if guest
      if (UserInfo.getUserType() == 'Guest') {
        summary.canWriteReview = false;
        summary.cannotReviewReason = 'Please log in to write a review.';
        return;
      }

      User u = [SELECT Id, ContactId FROM User WHERE Id = :userId LIMIT 1];
      if (u.ContactId == null) {
        summary.canWriteReview = false;
        summary.cannotReviewReason = 'You must be a registered customer.';
        return;
      }

      EligibilityResult er = checkEligibility(u.ContactId, productId);
      summary.canWriteReview = er.canReview;
      summary.cannotReviewReason = er.reason;
    } catch (Exception e) {
      summary.canWriteReview = false;
      summary.cannotReviewReason = 'Error checking eligibility';
    }
  }

  private static ReviewWrapper buildReviewWrapper(Review__c r) {
    ReviewWrapper rw = new ReviewWrapper();
    rw.id = r.Id;
    rw.name = r.Name;
    rw.rating = r.Rating__c.intValue();
    rw.title = r.Title__c;
    rw.comment = r.Comment__c;
    rw.customerName = r.Customer_Name__c;
    rw.customerType = r.Customer_Type__c;
    rw.recommended = r.Recommended__c;
    rw.isRecommended = (r.Recommended__c == 'Yes');
    rw.createdDate = r.CreatedDate.format();
    rw.createdDateFormatted = r.CreatedDate.format('MMM d, yyyy');

    // Build stars array : [1,1,1,1,0] for 4 stars
    rw.starsArray = new List<Integer>();
    for (Integer i = 1; i <= 5; i++) {
      rw.starsArray.add(i <= rw.rating ? 1 : 0);
    }
    return rw;
  }
}
