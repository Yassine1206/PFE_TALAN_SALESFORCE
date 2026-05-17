public without sharing class CkB2BDashboardController {
  @AuraEnabled(cacheable=true)
  public static DashboardData getDashboardData() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      if (accountId == null) {
        throw new AuraHandledException(
          'No B2B Account associated with this user.'
        );
      }

      DashboardData data = new DashboardData();

      // ─── Account info ─────────────────────────────────
      Account acc = CkB2BDashboardService.getAccountInfo(accountId);
      data.accountId = accountId;
      data.accountName = acc != null ? acc.Name : '';
      data.accountIndustry = acc != null ? acc.Industry : '';
      data.accountCity = acc != null ? acc.BillingCity : '';
      data.memberSince = acc != null ? acc.CreatedDate : null;
      data.annualGoal = acc != null &&
        acc.Annual_Goal__c != null
        ? acc.Annual_Goal__c
        : 50000;

      // ─── User info ────────────────────────────────────
      User u = [
        SELECT FirstName, LastName, Email
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      data.userFirstName = u.FirstName;
      data.userLastName = u.LastName;
      data.userEmail = u.Email;

      // ─── Hero stats ───────────────────────────────────
      Map<String, Object> heroStats = CkB2BDashboardService.getHeroStats(
        accountId
      );
      data.pendingQuotes = (Integer) heroStats.get('pendingQuotes');
      data.activeContracts = (Integer) heroStats.get('activeContracts');
      data.ytdSpend = (Decimal) heroStats.get('ytdSpend');

      // ─── Metrics with comparisons ─────────────────────
      data.metrics = CkB2BDashboardService.getMetrics(accountId);

      // ─── Revenue trend ────────────────────────────────
      data.revenueTrend = CkB2BDashboardService.getRevenueTrend(accountId);

      // ─── Spending by category ─────────────────────────
      data.spendingByCategory = CkB2BDashboardService.getSpendingByCategory(
        accountId
      );

      // ─── Quotes pipeline ──────────────────────────────
      data.quotesPipeline = CkB2BDashboardService.getQuotesPipeline(accountId);

      // ─── Activity feed ────────────────────────────────
      data.activityFeed = CkB2BDashboardService.getActivityFeed(accountId);

      // ─── Tier info ────────────────────────────────────
      data.tierInfo = CkB2BDashboardService.getTierInfo(
        accountId,
        data.ytdSpend
      );

      // ─── AI insights ──────────────────────────────────
      data.insights = CkB2BDashboardService.getInsights(
        accountId,
        data.tierInfo,
        data.ytdSpend
      );

      // ─── Forecast (simple) ────────────────────────────
      data.forecast = CkB2BDashboardService.getForecast(
        accountId,
        data.revenueTrend
      );

      // ─── Cost savings ─────────────────────────────────
      data.costSavings = CkB2BDashboardService.getCostSavings(accountId);

      // ─── Health score ─────────────────────────────────
      data.healthScore = CkB2BDashboardService.getHealthScore(
        accountId,
        data.ytdSpend
      );

      return data;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading dashboard: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getAdvancedData() {
    try {
      return CkB2BDashboardService.getAdvancedData();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to load advanced data: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getSection5Data() {
    try {
      return CkB2BDashboardService.getSection5Data();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to load Section 5 data: ' + e.getMessage()
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Returns Section 6 data: Health Score + Cost Savings + Forecast + AI Insights.
  // ═══════════════════════════════════════════════════════════
  @AuraEnabled
  public static Map<String, Object> getInsightsData() {
    try {
      return CkB2BDashboardService.getInsightsData();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to load insights data: ' + e.getMessage()
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SECONDARY METHODS — called separately for perf reasons
  // ═══════════════════════════════════════════════════════════

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getHeatmapData() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getHeatmapForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading heatmap: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getGeoData() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getGeoDataForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading geo data: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getTopProducts() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getTopProductsForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading top products: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getTeamActivity() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getTeamActivityForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException('Error loading team: ' + e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getSankeyData() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getSankeyForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException('Error loading sankey: ' + e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getRecommendedProducts() {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      return getRecommendedForAccount(accountId);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading recommendations: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static void saveAnnualGoal(Decimal newGoal) {
    try {
      Id accountId = CkB2BDashboardService.getCurrentUserAccountId();
      if (accountId == null) {
        throw new AuraHandledException('No account found.');
      }
      update new Account(Id = accountId, Annual_Goal__c = newGoal);
    } catch (Exception e) {
      throw new AuraHandledException('Error saving goal: ' + e.getMessage());
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PRIVATE HELPERS — for secondary methods
  // ═══════════════════════════════════════════════════════════

  private static List<Map<String, Object>> getHeatmapForAccount(Id accountId) {
    Date oneYearAgo = Date.today().addDays(-365);

    // Quotes — CreatedDate is Datetime, use DAY_ONLY()
    AggregateResult[] quoteResults = [
      SELECT DAY_ONLY(CreatedDate) day, COUNT(Id) cnt
      FROM Quote
      WHERE Opportunity.AccountId = :accountId AND CreatedDate >= :oneYearAgo
      GROUP BY DAY_ONLY(CreatedDate)
    ];

    // Orders — EffectiveDate is Date (no time), GROUP BY directly on the field
    AggregateResult[] orderResults = [
      SELECT EffectiveDate day, COUNT(Id) cnt
      FROM Order
      WHERE AccountId = :accountId AND EffectiveDate >= :oneYearAgo
      GROUP BY EffectiveDate
    ];

    // Build a date → count map
    Map<Date, Integer> dailyMap = new Map<Date, Integer>();
    for (AggregateResult r : quoteResults) {
      Date d = (Date) r.get('day');
      Integer c = (Integer) r.get('cnt');
      dailyMap.put(d, (dailyMap.containsKey(d) ? dailyMap.get(d) : 0) + c);
    }
    for (AggregateResult r : orderResults) {
      Date d = (Date) r.get('day');
      Integer c = (Integer) r.get('cnt');
      dailyMap.put(d, (dailyMap.containsKey(d) ? dailyMap.get(d) : 0) + c);
    }

    // Generate 365 entries (each day for the past year)
    List<Map<String, Object>> heatmap = new List<Map<String, Object>>();
    Date cursor = oneYearAgo;
    for (Integer i = 0; i < 365; i++) {
      Integer count = dailyMap.containsKey(cursor) ? dailyMap.get(cursor) : 0;
      Integer level;
      if (count == 0)
        level = 0;
      else if (count == 1)
        level = 1;
      else if (count <= 3)
        level = 2;
      else if (count <= 5)
        level = 3;
      else
        level = 4;

      heatmap.add(
        new Map<String, Object>{
          'date' => String.valueOf(cursor),
          'count' => count,
          'level' => level
        }
      );
      cursor = cursor.addDays(1);
    }
    return heatmap;
  }

  private static List<Map<String, Object>> getGeoDataForAccount(Id accountId) {
    // Returns the Account location for the map
    Account acc = CkB2BDashboardService.getAccountInfo(accountId);
    if (acc == null)
      return new List<Map<String, Object>>();

    Integer orderCount = [
      SELECT COUNT()
      FROM Order
      WHERE AccountId = :accountId
    ];

    return new List<Map<String, Object>>{
      new Map<String, Object>{
        'name' => acc.Name,
        'city' => acc.BillingCity,
        'lat' => acc.BillingLatitude,
        'lng' => acc.BillingLongitude,
        'orders' => orderCount
      }
    };
  }

  private static List<Map<String, Object>> getTopProductsForAccount(
    Id accountId
  ) {
    AggregateResult[] results = [
      SELECT
        Product2.Id pid,
        Product2.Name pname,
        Product2.Image_URL__c img,
        Product2.Product_Category__r.Name catName,
        Product2.B2B_Price__c b2bPrice,
        SUM(Quantity) qty,
        SUM(TotalPrice) total
      FROM OrderItem
      WHERE Order.AccountId = :accountId
      GROUP BY
        Product2.Id,
        Product2.Name,
        Product2.Image_URL__c,
        Product2.Product_Category__r.Name,
        Product2.B2B_Price__c
      ORDER BY SUM(TotalPrice) DESC
      LIMIT 5
    ];

    List<Map<String, Object>> products = new List<Map<String, Object>>();
    for (AggregateResult r : results) {
      products.add(
        new Map<String, Object>{
          'id' => r.get('pid'),
          'name' => r.get('pname'),
          'image' => r.get('img'),
          'category' => r.get('catName'),
          'price' => r.get('b2bPrice'),
          'quantity' => r.get('qty'),
          'total' => r.get('total')
        }
      );
    }
    return products;
  }

  private static List<Map<String, Object>> getTeamActivityForAccount(
    Id accountId
  ) {
    // List all contacts of this account with their activity
    List<Contact> contacts = [
      SELECT Id, FirstName, LastName, Title, Email
      FROM Contact
      WHERE AccountId = :accountId
      ORDER BY LastName ASC
    ];

    List<Map<String, Object>> team = new List<Map<String, Object>>();
    for (Contact c : contacts) {
      // Count their quote activity
      Integer quoteCount = [SELECT COUNT() FROM Quote WHERE ContactId = :c.Id];

      // Sum the GrandTotal of their quotes
      AggregateResult[] spendR = [
        SELECT SUM(GrandTotal) total
        FROM Quote
        WHERE ContactId = :c.Id
      ];
      Decimal totalSpend = spendR.isEmpty() || spendR[0].get('total') == null
        ? 0
        : (Decimal) spendR[0].get('total');

      String firstLetter = String.isNotBlank(c.FirstName)
        ? c.FirstName.substring(0, 1).toUpperCase()
        : '?';
      String lastLetter = String.isNotBlank(c.LastName)
        ? c.LastName.substring(0, 1).toUpperCase()
        : '';

      team.add(
        new Map<String, Object>{
          'id' => c.Id,
          'firstName' => c.FirstName,
          'lastName' => c.LastName,
          'fullName' => (c.FirstName + ' ' + c.LastName).trim(),
          'title' => c.Title,
          'email' => c.Email,
          'initials' => firstLetter + lastLetter,
          'quotes' => quoteCount,
          'spend' => totalSpend
        }
      );
    }
    return team;
  }

  private static Map<String, Object> getSankeyForAccount(Id accountId) {
    AggregateResult[] qr = [
      SELECT B2B_Status__c status, COUNT(Id) cnt
      FROM Quote
      WHERE Opportunity.AccountId = :accountId
      GROUP BY B2B_Status__c
    ];
    Map<String, Integer> qMap = new Map<String, Integer>{
      'Draft' => 0,
      'Sent to Customer' => 0,
      'Accepted' => 0,
      'Rejected' => 0,
      'Expired' => 0
    };
    Integer totalQuotes = 0;
    for (AggregateResult r : qr) {
      String s = (String) r.get('status');
      Integer c = (Integer) r.get('cnt');
      if (qMap.containsKey(s))
        qMap.put(s, c);
      totalQuotes += c;
    }

    Integer activeContracts = [
      SELECT COUNT()
      FROM Contract
      WHERE AccountId = :accountId AND Status = 'Activated'
    ];
    Integer totalOrders = [
      SELECT COUNT()
      FROM Order
      WHERE AccountId = :accountId
    ];

    return new Map<String, Object>{
      'totalQuotes' => totalQuotes,
      'sent' => qMap.get('Sent to Customer') +
      qMap.get('Accepted') +
      qMap.get('Rejected') +
      qMap.get('Expired'),
      'accepted' => qMap.get('Accepted'),
      'rejected' => qMap.get('Rejected'),
      'expired' => qMap.get('Expired'),
      'activeContracts' => activeContracts,
      'totalOrders' => totalOrders
    };
  }

  private static List<Map<String, Object>> getRecommendedForAccount(
    Id accountId
  ) {
    // Find top 3 categories from past orders
    AggregateResult[] catResults = [
      SELECT
        Product2.Product_Category__c catId,
        Product2.Product_Category__r.Name catName,
        SUM(Quantity) qty
      FROM OrderItem
      WHERE
        Order.AccountId = :accountId
        AND Product2.Product_Category__c != NULL
      GROUP BY Product2.Product_Category__c, Product2.Product_Category__r.Name
      ORDER BY SUM(Quantity) DESC
      LIMIT 3
    ];

    Set<Id> topCatIds = new Set<Id>();
    for (AggregateResult r : catResults) {
      topCatIds.add((Id) r.get('catId'));
    }

    // Find products in those categories that the user hasn't bought yet
    Set<Id> boughtProductIds = new Set<Id>();
    for (OrderItem oi : [
      SELECT Product2Id
      FROM OrderItem
      WHERE Order.AccountId = :accountId
    ]) {
      boughtProductIds.add(oi.Product2Id);
    }

    // Recommend products from top categories not yet bought
    List<Product2> products;
    if (!topCatIds.isEmpty()) {
      products = [
        SELECT
          Id,
          Name,
          Image_URL__c,
          B2B_Price__c,
          Rating__c,
          Product_Category__r.Name
        FROM Product2
        WHERE
          Product_Category__c IN :topCatIds
          AND Id NOT IN :boughtProductIds
          AND IsActive = TRUE
          AND B2B_Price__c != NULL
        ORDER BY Rating__c DESC NULLS LAST
        LIMIT 4
      ];
    } else {
      // Fallback: top-rated products overall
      products = [
        SELECT
          Id,
          Name,
          Image_URL__c,
          B2B_Price__c,
          Rating__c,
          Product_Category__r.Name
        FROM Product2
        WHERE IsActive = TRUE AND B2B_Price__c != NULL
        ORDER BY Rating__c DESC NULLS LAST
        LIMIT 4
      ];
    }

    List<Map<String, Object>> recommended = new List<Map<String, Object>>();
    for (Product2 p : products) {
      recommended.add(
        new Map<String, Object>{
          'id' => p.Id,
          'name' => p.Name,
          'image' => p.Image_URL__c,
          'price' => p.B2B_Price__c,
          'rating' => p.Rating__c,
          'category' => p.Product_Category__r != null
            ? p.Product_Category__r.Name
            : ''
        }
      );
    }
    return recommended;
  }
  /**
   * @description Returns Section 7 data: Tier + Recommended (AI) + Upcoming events.
   */
  @AuraEnabled
  public static Map<String, Object> getSection7Data() {
    try {
      return CkB2BDashboardService.getSection7Data();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to load Section 7 data: ' + e.getMessage()
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DTO — DashboardData wrapper
  // ═══════════════════════════════════════════════════════════

  public class DashboardData {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountIndustry;
    @AuraEnabled
    public String accountCity;
    @AuraEnabled
    public Datetime memberSince;
    @AuraEnabled
    public Decimal annualGoal;

    @AuraEnabled
    public String userFirstName;
    @AuraEnabled
    public String userLastName;
    @AuraEnabled
    public String userEmail;

    @AuraEnabled
    public Integer pendingQuotes;
    @AuraEnabled
    public Integer activeContracts;
    @AuraEnabled
    public Decimal ytdSpend;

    @AuraEnabled
    public List<Map<String, Object>> metrics;
    @AuraEnabled
    public List<Map<String, Object>> revenueTrend;
    @AuraEnabled
    public List<Map<String, Object>> spendingByCategory;
    @AuraEnabled
    public Map<String, Object> quotesPipeline;
    @AuraEnabled
    public List<Map<String, Object>> activityFeed;
    @AuraEnabled
    public Map<String, Object> tierInfo;
    @AuraEnabled
    public List<Map<String, Object>> insights;
    @AuraEnabled
    public Map<String, Object> forecast;
    @AuraEnabled
    public Map<String, Object> costSavings;
    @AuraEnabled
    public Map<String, Object> healthScore;
  }
}
