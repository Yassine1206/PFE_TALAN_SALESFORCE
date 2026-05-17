public without sharing class CkB2BDashboardService {
  private static final Decimal TIER_BRONZE_LIMIT = 5000;
  private static final Decimal TIER_SILVER_LIMIT = 25000;
  private static final Decimal TIER_GOLD_LIMIT = 50000;

  public static Id getCurrentUserAccountId() {
    User u = [
      SELECT Id, ContactId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return u.Contact != null ? u.Contact.AccountId : null;
  }

  public static Account getAccountInfo(Id accountId) {
    List<Account> accs = [
      SELECT
        Id,
        Name,
        Industry,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Annual_Goal__c,
        CreatedDate,
        AnnualRevenue
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    return accs.isEmpty() ? null : accs[0];
  }

  // ═══════════════════════════════════════════════════════════
  // HERO STATS
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getHeroStats(Id accountId) {
    Map<String, Object> stats = new Map<String, Object>();

    Integer pendingQuotes = [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c = 'Sent to Customer'
    ];
    stats.put('pendingQuotes', pendingQuotes);

    Integer activeContracts = [
      SELECT COUNT()
      FROM Contract
      WHERE AccountId = :accountId AND Status = 'Activated'
    ];
    stats.put('activeContracts', activeContracts);

    AggregateResult[] ytdResult = [
      SELECT SUM(TotalAmount) total
      FROM Order
      WHERE
        AccountId = :accountId
        AND CALENDAR_YEAR(EffectiveDate) = :Date.today().year()
    ];
    Decimal ytdSpend = ytdResult.isEmpty() || ytdResult[0].get('total') == null
      ? 0
      : (Decimal) ytdResult[0].get('total');
    stats.put('ytdSpend', ytdSpend);

    return stats;
  }

  // ═══════════════════════════════════════════════════════════
  // METRICS — 4 cards with month-over-month comparisons
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getMetrics(Id accountId) {
    List<Map<String, Object>> metrics = new List<Map<String, Object>>();
    Date today = Date.today();
    Date startOfMonth = today.toStartOfMonth();
    Date startOfLastMonth = startOfMonth.addMonths(-1);
    Date endOfLastMonth = startOfMonth.addDays(-1);

    Decimal thisMonthSpent = sumOrdersInRange(accountId, startOfMonth, today);
    Decimal lastMonthSpent = sumOrdersInRange(
      accountId,
      startOfLastMonth,
      endOfLastMonth
    );
    metrics.add(
      buildMetric(
        'totalSpent',
        'Total Spent',
        thisMonthSpent,
        lastMonthSpent,
        'currency',
        'higherIsBetter'
      )
    );

    Integer thisMonthQuotes = countQuotesInRange(
      accountId,
      startOfMonth,
      today
    );
    Integer lastMonthQuotes = countQuotesInRange(
      accountId,
      startOfLastMonth,
      endOfLastMonth
    );
    metrics.add(
      buildMetric(
        'quotes',
        'Quotes',
        thisMonthQuotes,
        lastMonthQuotes,
        'number',
        'higherIsBetter'
      )
    );

    Integer thisMonthOrders = countOrdersInRange(
      accountId,
      startOfMonth,
      today
    );
    Integer lastMonthOrders = countOrdersInRange(
      accountId,
      startOfLastMonth,
      endOfLastMonth
    );
    metrics.add(
      buildMetric(
        'orders',
        'Orders',
        thisMonthOrders,
        lastMonthOrders,
        'number',
        'higherIsBetter'
      )
    );

    Decimal thisMonthAvgResp = computeAvgResponseTime(
      accountId,
      startOfMonth,
      today
    );
    Decimal lastMonthAvgResp = computeAvgResponseTime(
      accountId,
      startOfLastMonth,
      endOfLastMonth
    );
    metrics.add(
      buildMetric(
        'avgResponse',
        'Avg Response',
        thisMonthAvgResp,
        lastMonthAvgResp,
        'days',
        'lowerIsBetter'
      )
    );

    return metrics;
  }

  // ═══════════════════════════════════════════════════════════
  // REVENUE TREND — 12 months for line chart
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getRevenueTrend(Id accountId) {
    List<Map<String, Object>> trend = new List<Map<String, Object>>();
    Date today = Date.today();
    Date startMonth = today.toStartOfMonth().addMonths(-11);

    AggregateResult[] results = [
      SELECT
        CALENDAR_YEAR(EffectiveDate) yr,
        CALENDAR_MONTH(EffectiveDate) mo,
        SUM(TotalAmount) total
      FROM Order
      WHERE AccountId = :accountId AND EffectiveDate >= :startMonth
      GROUP BY CALENDAR_YEAR(EffectiveDate), CALENDAR_MONTH(EffectiveDate)
    ];

    Map<String, Decimal> monthlyMap = new Map<String, Decimal>();
    for (AggregateResult r : results) {
      String key =
        String.valueOf(r.get('yr')) +
        '-' +
        String.valueOf(r.get('mo'));
      monthlyMap.put(
        key,
        r.get('total') != null ? (Decimal) r.get('total') : 0
      );
    }

    Date cursor = startMonth;
    for (Integer i = 0; i < 12; i++) {
      String key = cursor.year() + '-' + cursor.month();
      Decimal total = monthlyMap.containsKey(key) ? monthlyMap.get(key) : 0;
      trend.add(
        new Map<String, Object>{
          'label' => monthName(cursor.month()) +
          ' ' +
          String.valueOf(cursor.year()).substring(2),
          'value' => total,
          'year' => cursor.year(),
          'month' => cursor.month()
        }
      );
      cursor = cursor.addMonths(1);
    }
    return trend;
  }

  // ═══════════════════════════════════════════════════════════
  // SPENDING BY CATEGORY — Donut chart
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getSpendingByCategory(Id accountId) {
    Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);

    AggregateResult[] results = [
      SELECT Product2.Product_Category__r.Name catName, SUM(TotalPrice) total
      FROM OrderItem
      WHERE
        Order.AccountId = :accountId
        AND Order.EffectiveDate >= :startOfYear
        AND Product2.Product_Category__c != NULL
      GROUP BY Product2.Product_Category__r.Name
      ORDER BY SUM(TotalPrice) DESC
      LIMIT 5
    ];

    List<Map<String, Object>> categories = new List<Map<String, Object>>();
    for (AggregateResult r : results) {
      categories.add(
        new Map<String, Object>{
          'category' => r.get('catName'),
          'total' => r.get('total') != null ? (Decimal) r.get('total') : 0
        }
      );
    }
    return categories;
  }

  // ═══════════════════════════════════════════════════════════
  // QUOTES PIPELINE — Bar chart funnel
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getQuotesPipeline(Id accountId) {
    AggregateResult[] results = [
      SELECT B2B_Status__c status, COUNT(Id) cnt
      FROM Quote
      WHERE Opportunity.AccountId = :accountId
      GROUP BY B2B_Status__c
    ];

    Map<String, Integer> statusMap = new Map<String, Integer>{
      'Draft' => 0,
      'Sent to Customer' => 0,
      'Accepted' => 0,
      'Rejected' => 0,
      'Expired' => 0
    };

    Integer total = 0;
    for (AggregateResult r : results) {
      String status = (String) r.get('status');
      Integer cnt = (Integer) r.get('cnt');
      if (statusMap.containsKey(status))
        statusMap.put(status, cnt);
      total += cnt;
    }

    Integer accepted = statusMap.get('Accepted');
    Integer sent =
      statusMap.get('Sent to Customer') +
      accepted +
      statusMap.get('Rejected') +
      statusMap.get('Expired');
    Decimal conversion = sent > 0
      ? (Decimal.valueOf(accepted) / sent) * 100
      : 0;

    return new Map<String, Object>{
      'draft' => statusMap.get('Draft'),
      'sent' => statusMap.get('Sent to Customer'),
      'accepted' => statusMap.get('Accepted'),
      'rejected' => statusMap.get('Rejected'),
      'expired' => statusMap.get('Expired'),
      'total' => total,
      'conversion' => conversion.setScale(0)
    };
  }

  // ═══════════════════════════════════════════════════════════
  // ACTIVITY FEED — Top 5 mixed events
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getActivityFeed(Id accountId) {
    List<Map<String, Object>> feed = new List<Map<String, Object>>();

    for (Quote q : [
      SELECT Id, QuoteNumber, GrandTotal, B2B_Status__c, LastModifiedDate
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c = 'Sent to Customer'
      ORDER BY LastModifiedDate DESC
      LIMIT 3
    ]) {
      feed.add(
        new Map<String, Object>{
          'type' => 'quote',
          'icon' => 'quote',
          'color' => '#1971C2',
          'title' => 'Quote ' +
          q.QuoteNumber +
          ' sent to you',
          'subtitle' => '$' + (q.GrandTotal == null ? 0 : q.GrandTotal),
          'datetime' => q.LastModifiedDate
        }
      );
    }

    for (Contract c : [
      SELECT Id, ContractNumber, ContractTerm, ActivatedDate
      FROM Contract
      WHERE AccountId = :accountId AND Status = 'Activated'
      ORDER BY ActivatedDate DESC NULLS LAST
      LIMIT 2
    ]) {
      feed.add(
        new Map<String, Object>{
          'type' => 'contract',
          'icon' => 'contract',
          'color' => '#1D9E75',
          'title' => 'Contract C-' +
          c.ContractNumber +
          ' activated',
          'subtitle' => c.ContractTerm + ' months',
          'datetime' => c.ActivatedDate != null
            ? (Datetime) c.ActivatedDate
            : Datetime.now()
        }
      );
    }

    for (Order o : [
      SELECT Id, OrderNumber, TotalAmount, Status, EffectiveDate
      FROM Order
      WHERE AccountId = :accountId
      ORDER BY EffectiveDate DESC NULLS LAST
      LIMIT 2
    ]) {
      feed.add(
        new Map<String, Object>{
          'type' => 'order',
          'icon' => 'order',
          'color' => '#FF6B1A',
          'title' => 'Order ' +
          o.OrderNumber +
          ' ' +
          o.Status.toLowerCase(),
          'subtitle' => '$' + (o.TotalAmount == null ? 0 : o.TotalAmount),
          'datetime' => o.EffectiveDate != null
            ? (Datetime) o.EffectiveDate
            : Datetime.now()
        }
      );
    }

    feed.sort(new ActivityComparator());
    if (feed.size() > 5) {
      List<Map<String, Object>> top5 = new List<Map<String, Object>>();
      for (Integer i = 0; i < 5; i++)
        top5.add(feed[i]);
      return top5;
    }
    return feed;
  }

  public class ActivityComparator implements Comparator<Map<String, Object>> {
    public Integer compare(Map<String, Object> a, Map<String, Object> b) {
      Datetime da = (Datetime) a.get('datetime');
      Datetime db = (Datetime) b.get('datetime');
      if (da > db)
        return -1;
      if (da < db)
        return 1;
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TIER SYSTEM — Bronze / Silver / Gold / Platinum
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getTierInfo(
    Id accountId,
    Decimal ytdSpend
  ) {
    String currentTier;
    Decimal nextTierLimit;
    String nextTier;
    List<String> benefits = new List<String>();

    if (ytdSpend < TIER_BRONZE_LIMIT) {
      currentTier = 'Bronze';
      nextTier = 'Silver';
      nextTierLimit = TIER_BRONZE_LIMIT;
      benefits.add('Standard B2B pricing');
    } else if (ytdSpend < TIER_SILVER_LIMIT) {
      currentTier = 'Silver';
      nextTier = 'Gold';
      nextTierLimit = TIER_SILVER_LIMIT;
      benefits.add('5% volume discount');
      benefits.add('Priority support');
      benefits.add('Early access to new products');
    } else if (ytdSpend < TIER_GOLD_LIMIT) {
      currentTier = 'Gold';
      nextTier = 'Platinum';
      nextTierLimit = TIER_GOLD_LIMIT;
      benefits.add('10% volume discount');
      benefits.add('Dedicated account manager');
      benefits.add('Free shipping on all orders');
      benefits.add('Quarterly business reviews');
    } else {
      currentTier = 'Platinum';
      nextTier = null;
      nextTierLimit = null;
      benefits.add('15% volume discount');
      benefits.add('Custom contract terms');
      benefits.add('White-glove service');
      benefits.add('VIP events access');
    }

    Decimal progress = nextTierLimit != null
      ? (ytdSpend / nextTierLimit) * 100
      : 100;
    Decimal toNextTier = nextTierLimit != null ? nextTierLimit - ytdSpend : 0;

    return new Map<String, Object>{
      'currentTier' => currentTier,
      'nextTier' => nextTier,
      'ytdSpend' => ytdSpend,
      'nextTierLimit' => nextTierLimit,
      'progress' => progress.setScale(1),
      'toNextTier' => toNextTier,
      'benefits' => benefits
    };
  }

  // ═══════════════════════════════════════════════════════════
  // AI INSIGHTS
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getInsights(
    Id accountId,
    Map<String, Object> tierInfo,
    Decimal ytdSpend
  ) {
    List<Map<String, Object>> insights = new List<Map<String, Object>>();

    String tier = (String) tierInfo.get('currentTier');
    if (tier == 'Silver' || tier == 'Gold' || tier == 'Platinum') {
      Decimal discount = tier == 'Silver' ? 0.05 : tier == 'Gold' ? 0.10 : 0.15;
      Decimal saved = ytdSpend * discount;
      insights.add(
        new Map<String, Object>{
          'icon' => 'trophy',
          'color' => '#FF6B1A',
          'title' => 'Tier savings',
          'text' => 'You saved $' +
          saved.setScale(0).format() +
          ' YTD thanks to your ' +
          tier +
          ' tier'
        }
      );
    }

    Integer expiringSoon = [
      SELECT COUNT()
      FROM Contract
      WHERE
        AccountId = :accountId
        AND Status = 'Activated'
        AND EndDate <= :Date.today().addDays(30)
        AND EndDate >= :Date.today()
    ];
    if (expiringSoon > 0) {
      insights.add(
        new Map<String, Object>{
          'icon' => 'alert',
          'color' => '#E24B4A',
          'title' => 'Contracts expiring',
          'text' => expiringSoon +
          ' contract(s) expire within 30 days — plan renewal now'
        }
      );
    }

    Integer recentQuotes = [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND CreatedDate >= :Date.today().toStartOfMonth().toStartOfWeek()
    ];
    if (recentQuotes >= 3) {
      insights.add(
        new Map<String, Object>{
          'icon' => 'trending-up',
          'color' => '#1D9E75',
          'title' => 'Active month',
          'text' => 'You requested ' +
          recentQuotes +
          ' quotes this month — your business is growing'
        }
      );
    }

    return insights;
  }

  // ═══════════════════════════════════════════════════════════
  // FORECAST — Moving average over last 3 months
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getForecast(
    Id accountId,
    List<Map<String, Object>> revenueTrend
  ) {
    if (revenueTrend.size() < 3) {
      return new Map<String, Object>{ 'forecast' => 0, 'confidence' => 'low' };
    }

    Decimal sum = 0;
    Integer count = 0;
    for (Integer i = revenueTrend.size() - 3; i < revenueTrend.size(); i++) {
      Decimal v = (Decimal) revenueTrend[i].get('value');
      sum += v;
      count++;
    }
    Decimal avg = count > 0 ? sum / count : 0;

    return new Map<String, Object>{
      'nextMonthForecast' => avg.setScale(0),
      'q3Forecast' => (avg * 3).setScale(0),
      'confidence' => count == 3 ? 'medium' : 'low',
      'trend' => avg > 0 ? 'positive' : 'flat'
    };
  }

  // ═══════════════════════════════════════════════════════════
  // COST SAVINGS — B2B vs retail comparison
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getCostSavings(Id accountId) {
    Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);

    AggregateResult[] results = [
      SELECT SUM(Quantity) qty, SUM(TotalPrice) b2bTotal
      FROM OrderItem
      WHERE
        Order.AccountId = :accountId
        AND Order.EffectiveDate >= :startOfYear
        AND Product2.B2B_Price__c != NULL
    ];

    Decimal totalQty = results.isEmpty() || results[0].get('qty') == null
      ? 0
      : (Decimal) results[0].get('qty');
    Decimal b2bTotal = results.isEmpty() || results[0].get('b2bTotal') == null
      ? 0
      : (Decimal) results[0].get('b2bTotal');

    Decimal retailEquivalent = b2bTotal > 0 ? b2bTotal / 0.85 : 0;
    Decimal saved = retailEquivalent - b2bTotal;
    Decimal savedPct = retailEquivalent > 0
      ? (saved / retailEquivalent) * 100
      : 0;

    return new Map<String, Object>{
      'totalSaved' => saved.setScale(0),
      'savedPct' => savedPct.setScale(0),
      'b2bSpent' => b2bTotal.setScale(0),
      'retailEquiv' => retailEquivalent.setScale(0),
      'unitsBought' => (Integer) totalQty
    };
  }

  // ═══════════════════════════════════════════════════════════
  // HEALTH SCORE — 0-100 composite score
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getHealthScore(
    Id accountId,
    Decimal ytdSpend
  ) {
    Integer score = 0;
    List<Map<String, Object>> breakdown = new List<Map<String, Object>>();

    Integer volumePts = (Integer) Math.min(40, (ytdSpend / 50000) * 40);
    score += volumePts;
    breakdown.add(
      new Map<String, Object>{
        'label' => 'Volume',
        'score' => volumePts,
        'max' => 40
      }
    );

    Integer orderCount = [
      SELECT COUNT()
      FROM Order
      WHERE
        AccountId = :accountId
        AND EffectiveDate >= :Date.today().addMonths(-6)
    ];
    Integer regularityPts = (Integer) Math.min(20, orderCount * 4);
    score += regularityPts;
    breakdown.add(
      new Map<String, Object>{
        'label' => 'Order regularity',
        'score' => regularityPts,
        'max' => 20
      }
    );

    Integer respondedQuotes = [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c IN ('Accepted', 'Rejected')
    ];
    Integer sentQuotes = [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c IN (
          'Accepted',
          'Rejected',
          'Expired',
          'Sent to Customer'
        )
    ];
    Integer responsePts = sentQuotes > 0
      ? (Integer) Math.min(
          20,
          (Decimal.valueOf(respondedQuotes) / sentQuotes) * 20
        )
      : 10;
    score += responsePts;
    breakdown.add(
      new Map<String, Object>{
        'label' => 'Response rate',
        'score' => responsePts,
        'max' => 20
      }
    );

    Account acc = getAccountInfo(accountId);
    Integer monthsActive = acc != null
      ? Date.today().monthsBetween(acc.CreatedDate.date()) * -1
      : 0;
    Integer longevityPts = (Integer) Math.min(20, monthsActive);
    score += longevityPts;
    breakdown.add(
      new Map<String, Object>{
        'label' => 'Longevity',
        'score' => longevityPts,
        'max' => 20
      }
    );

    score = (Integer) Math.min(100, score);

    String rating;
    if (score >= 80)
      rating = 'Excellent';
    else if (score >= 60)
      rating = 'Good';
    else if (score >= 40)
      rating = 'Fair';
    else
      rating = 'Building';

    return new Map<String, Object>{
      'score' => score,
      'rating' => rating,
      'breakdown' => breakdown
    };
  }

  // ═══════════════════════════════════════════════════════════
  // HEATMAP — GitHub-style activity for last 365 days
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getHeatmapData(Id accountId) {
    Date today = Date.today();
    Date startDate = today.addDays(-365);

    Map<String, List<Map<String, Object>>> activityMap = new Map<String, List<Map<String, Object>>>();

    for (Order o : [
      SELECT Id, OrderNumber, TotalAmount, Status, EffectiveDate
      FROM Order
      WHERE AccountId = :accountId AND EffectiveDate >= :startDate
      ORDER BY EffectiveDate DESC
    ]) {
      String key = String.valueOf(o.EffectiveDate);
      if (!activityMap.containsKey(key)) {
        activityMap.put(key, new List<Map<String, Object>>());
      }
      Decimal amt = o.TotalAmount != null ? o.TotalAmount : 0;
      activityMap.get(key)
        .add(
          new Map<String, Object>{
            'type' => 'order',
            'id' => o.Id,
            'reference' => o.OrderNumber,
            'title' => 'Order ' +
            o.OrderNumber +
            ' placed',
            'amount' => amt.setScale(0),
            'status' => o.Status,
            'url' => '/TalFlowExpress/s/order/' + o.Id
          }
        );
    }

    for (Quote q : [
      SELECT Id, QuoteNumber, GrandTotal, B2B_Status__c, CreatedDate
      FROM Quote
      WHERE Opportunity.AccountId = :accountId AND CreatedDate >= :startDate
      ORDER BY CreatedDate DESC
    ]) {
      String key = String.valueOf(q.CreatedDate.date());
      if (!activityMap.containsKey(key)) {
        activityMap.put(key, new List<Map<String, Object>>());
      }
      Decimal amt = q.GrandTotal != null ? q.GrandTotal : 0;
      activityMap.get(key)
        .add(
          new Map<String, Object>{
            'type' => 'quote',
            'id' => q.Id,
            'reference' => q.QuoteNumber,
            'title' => 'Quote ' +
            q.QuoteNumber +
            ' created',
            'amount' => amt.setScale(0),
            'status' => q.B2B_Status__c != null ? q.B2B_Status__c : 'Draft',
            'url' => '/TalFlowExpress/s/my-quotes'
          }
        );
    }

    List<Map<String, Object>> heatmap = new List<Map<String, Object>>();
    Date cursor = startDate;
    while (cursor <= today) {
      String key = String.valueOf(cursor);
      List<Map<String, Object>> dayActivities = activityMap.containsKey(key)
        ? activityMap.get(key)
        : new List<Map<String, Object>>();

      heatmap.add(
        new Map<String, Object>{
          'date' => key,
          'count' => dayActivities.size(),
          'activities' => dayActivities,
          'year' => cursor.year(),
          'month' => cursor.month(),
          'day' => cursor.day()
        }
      );
      cursor = cursor.addDays(1);
    }
    return heatmap;
  }

  // ═══════════════════════════════════════════════════════════
  // ADVANCED DATA — Heatmap (Session 4)
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getAdvancedData() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      return new Map<String, Object>{
        'heatmap' => new List<Map<String, Object>>()
      };
    }
    return new Map<String, Object>{ 'heatmap' => getHeatmapData(accountId) };
  }

  // ═══════════════════════════════════════════════════════════
  // GEO DATA — User location + B2B network stats
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getGeoData(Id accountId) {
    Account acc = getAccountInfo(accountId);
    if (acc == null)
      return new Map<String, Object>();

    Integer totalB2B = [
      SELECT COUNT()
      FROM Account
      WHERE Account_Type__c = 'B2B'
    ];

    Integer sameCountry = acc.BillingCountry != null
      ? [
          SELECT COUNT()
          FROM Account
          WHERE Account_Type__c = 'B2B' AND BillingCountry = :acc.BillingCountry
        ]
      : 0;

    Integer sameCity = acc.BillingCity != null
      ? [
          SELECT COUNT()
          FROM Account
          WHERE Account_Type__c = 'B2B' AND BillingCity = :acc.BillingCity
        ]
      : 0;

    return new Map<String, Object>{
      'userCity' => acc.BillingCity != null ? acc.BillingCity : 'Unknown',
      'userCountry' => acc.BillingCountry != null
        ? acc.BillingCountry
        : 'Unknown',
      'userLat' => acc.BillingLatitude != null ? acc.BillingLatitude : 36.8,
      'userLng' => acc.BillingLongitude != null ? acc.BillingLongitude : 10.2,
      'totalB2B' => totalB2B,
      'sameCountry' => sameCountry,
      'sameCity' => sameCity
    };
  }

  // ═══════════════════════════════════════════════════════════
  // TOP 5 PRODUCTS — by spending YTD
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getTopProducts(Id accountId) {
    Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);

    AggregateResult[] results = [
      SELECT
        Product2Id productId,
        Product2.Name productName,
        Product2.Image_URL__c imageUrl,
        Product2.Product_Category__r.Name categoryName,
        SUM(Quantity) totalQty,
        SUM(TotalPrice) totalSpent
      FROM OrderItem
      WHERE Order.AccountId = :accountId AND Order.EffectiveDate >= :startOfYear
      GROUP BY
        Product2Id,
        Product2.Name,
        Product2.Image_URL__c,
        Product2.Product_Category__r.Name
      ORDER BY SUM(TotalPrice) DESC
      LIMIT 5
    ];

    List<Map<String, Object>> top = new List<Map<String, Object>>();
    Integer rank = 1;
    for (AggregateResult r : results) {
      Decimal totalSpent = r.get('totalSpent') != null
        ? (Decimal) r.get('totalSpent')
        : 0;
      Decimal totalQty = r.get('totalQty') != null
        ? (Decimal) r.get('totalQty')
        : 0;
      top.add(
        new Map<String, Object>{
          'rank' => rank++,
          'productId' => r.get('productId'),
          'name' => r.get('productName'),
          'imageUrl' => r.get('imageUrl'),
          'category' => r.get('categoryName') != null
            ? r.get('categoryName')
            : 'Uncategorized',
          'totalQty' => totalQty.intValue(),
          'totalSpent' => totalSpent.setScale(0)
        }
      );
    }
    return top;
  }

  // ═══════════════════════════════════════════════════════════
  // NOTIFICATIONS — Smart business notifications (top 5)
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getNotifications(Id accountId) {
    List<Map<String, Object>> notifs = new List<Map<String, Object>>();

    for (Quote q : [
      SELECT Id, QuoteNumber, GrandTotal, ExpirationDate, LastModifiedDate
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c = 'Sent to Customer'
      ORDER BY LastModifiedDate DESC
      LIMIT 3
    ]) {
      Integer daysToExpire = q.ExpirationDate != null
        ? Date.today().daysBetween(q.ExpirationDate)
        : 9999;
      String priority = daysToExpire <= 7 ? 'high' : 'normal';
      Decimal amount = q.GrandTotal != null ? q.GrandTotal : 0;
      notifs.add(
        new Map<String, Object>{
          'iconType' => 'quote',
          'priority' => priority,
          'title' => 'Quote ' +
          q.QuoteNumber +
          ' awaiting review',
          'subtitle' => '$' +
          amount.setScale(0).format() +
          (daysToExpire < 9999
            ? ' · expires in ' + daysToExpire + ' days'
            : ''),
          'actionUrl' => '/TalFlowExpress/s/my-quotes',
          'actionLabel' => 'Review',
          'datetime' => q.LastModifiedDate
        }
      );
    }

    for (Contract c : [
      SELECT Id, ContractNumber, ActivatedDate, EndDate
      FROM Contract
      WHERE AccountId = :accountId AND Status = 'Activated'
      ORDER BY ActivatedDate DESC NULLS LAST
      LIMIT 1
    ]) {
      notifs.add(
        new Map<String, Object>{
          'iconType' => 'contract',
          'priority' => 'normal',
          'title' => 'Contract C-' +
          c.ContractNumber +
          ' is now active',
          'subtitle' => 'Valid until ' +
          (c.EndDate != null ? c.EndDate.format() : 'TBD'),
          'actionUrl' => '/TalFlowExpress/s/my-contracts',
          'actionLabel' => 'View',
          'datetime' => c.ActivatedDate != null
            ? (Datetime) c.ActivatedDate
            : Datetime.now()
        }
      );
    }

    for (Contract c : [
      SELECT Id, ContractNumber, EndDate
      FROM Contract
      WHERE
        AccountId = :accountId
        AND Status = 'Activated'
        AND EndDate <= :Date.today().addDays(30)
        AND EndDate >= :Date.today()
      ORDER BY EndDate ASC
      LIMIT 2
    ]) {
      Integer daysLeft = Date.today().daysBetween(c.EndDate);
      notifs.add(
        new Map<String, Object>{
          'iconType' => 'alert',
          'priority' => 'high',
          'title' => 'Contract C-' +
          c.ContractNumber +
          ' expires soon',
          'subtitle' => 'Only ' +
          daysLeft +
          ' days left — renew now',
          'actionUrl' => '/TalFlowExpress/s/my-contracts',
          'actionLabel' => 'Renew',
          'datetime' => Datetime.now()
        }
      );
    }

    for (Order o : [
      SELECT Id, OrderNumber, TotalAmount, EffectiveDate
      FROM Order
      WHERE AccountId = :accountId AND Status = 'Activated'
      ORDER BY EffectiveDate DESC NULLS LAST
      LIMIT 1
    ]) {
      Decimal amount = o.TotalAmount != null ? o.TotalAmount : 0;
      notifs.add(
        new Map<String, Object>{
          'iconType' => 'order',
          'priority' => 'normal',
          'title' => 'Order ' +
          o.OrderNumber +
          ' is being processed',
          'subtitle' => '$' +
          amount.setScale(0).format() +
          ' · activated',
          'actionUrl' => '/TalFlowExpress/s/my-orders',
          'actionLabel' => 'Track',
          'datetime' => o.EffectiveDate != null
            ? (Datetime) o.EffectiveDate
            : Datetime.now()
        }
      );
    }

    notifs.sort(new NotifComparator());

    List<Map<String, Object>> top5 = new List<Map<String, Object>>();
    Integer count = 0;
    for (Map<String, Object> n : notifs) {
      if (count >= 5)
        break;
      top5.add(n);
      count++;
    }
    return top5;
  }

  public class NotifComparator implements Comparator<Map<String, Object>> {
    public Integer compare(Map<String, Object> a, Map<String, Object> b) {
      String pa = (String) a.get('priority');
      String pb = (String) b.get('priority');
      if (pa == 'high' && pb != 'high')
        return -1;
      if (pb == 'high' && pa != 'high')
        return 1;
      Datetime da = (Datetime) a.get('datetime');
      Datetime db = (Datetime) b.get('datetime');
      if (da > db)
        return -1;
      if (da < db)
        return 1;
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION 5 DATA — Geo + Top Products + Notifications
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getSection5Data() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      return new Map<String, Object>{
        'geo' => new Map<String, Object>(),
        'topProducts' => new List<Map<String, Object>>(),
        'notifications' => new List<Map<String, Object>>()
      };
    }
    return new Map<String, Object>{
      'geo' => getGeoData(accountId),
      'topProducts' => getTopProducts(accountId),
      'notifications' => getNotifications(accountId)
    };
  }

  public static Map<String, Object> getInsightsData() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      return new Map<String, Object>{
        'healthScore' => new Map<String, Object>(),
        'costSavings' => new Map<String, Object>(),
        'forecast' => new Map<String, Object>(),
        'insights' => new List<Map<String, Object>>(),
        'aiPowered' => false
      };
    }

    Map<String, Object> heroStats = getHeroStats(accountId);
    Decimal ytdSpend = (Decimal) heroStats.get('ytdSpend');
    Map<String, Object> tierInfo = getTierInfo(accountId, ytdSpend);
    List<Map<String, Object>> revenueTrend = getRevenueTrend(accountId);

    // ─── AI Insights via Agentforce ───
    List<Map<String, Object>> aiInsights;
    Boolean aiPowered = true;
    try {
      aiInsights = CkAgentforceInsightsService.generateInsights(accountId);
      // Si l'IA renvoie une liste vide, on bascule sur le fallback
      if (aiInsights == null || aiInsights.isEmpty()) {
        System.debug('AI returned empty, falling back to rules');
        aiInsights = getInsights(accountId, tierInfo, ytdSpend);
        aiPowered = false;
      }
    } catch (Exception e) {
      System.debug(
        'AI generation failed, falling back to rules: ' + e.getMessage()
      );
      aiInsights = getInsights(accountId, tierInfo, ytdSpend);
      aiPowered = false;
    }

    return new Map<String, Object>{
      'healthScore' => getHealthScore(accountId, ytdSpend),
      'costSavings' => getCostSavings(accountId),
      'forecast' => getForecast(accountId, revenueTrend),
      'insights' => aiInsights,
      'tier' => tierInfo.get('currentTier'),
      'aiPowered' => aiPowered
    };
  }

  // ═══════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════

  private static Decimal sumOrdersInRange(
    Id accountId,
    Date startD,
    Date endD
  ) {
    AggregateResult[] r = [
      SELECT SUM(TotalAmount) total
      FROM Order
      WHERE
        AccountId = :accountId
        AND EffectiveDate >= :startD
        AND EffectiveDate <= :endD
    ];
    return r.isEmpty() || r[0].get('total') == null
      ? 0
      : (Decimal) r[0].get('total');
  }

  private static Integer countQuotesInRange(
    Id accountId,
    Date startD,
    Date endD
  ) {
    return [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND CreatedDate >= :startD
        AND CreatedDate <= :endD
    ];
  }

  private static Integer countOrdersInRange(
    Id accountId,
    Date startD,
    Date endD
  ) {
    return [
      SELECT COUNT()
      FROM Order
      WHERE
        AccountId = :accountId
        AND EffectiveDate >= :startD
        AND EffectiveDate <= :endD
    ];
  }

  private static Decimal computeAvgResponseTime(
    Id accountId,
    Date startD,
    Date endD
  ) {
    List<Quote> quotes = [
      SELECT CreatedDate, LastModifiedDate
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c IN ('Accepted', 'Rejected')
        AND LastModifiedDate >= :startD
        AND LastModifiedDate <= :endD
      LIMIT 100
    ];
    if (quotes.isEmpty())
      return 0;
    Decimal totalDays = 0;
    for (Quote q : quotes) {
      Long diffMs = q.LastModifiedDate.getTime() - q.CreatedDate.getTime();
      totalDays += diffMs / (1000.0 * 60 * 60 * 24);
    }
    return (totalDays / quotes.size()).setScale(1);
  }

  private static Map<String, Object> buildMetric(
    String key,
    String label,
    Decimal current,
    Decimal previous,
    String format,
    String mode
  ) {
    Decimal change = previous != 0
      ? ((current - previous) / previous) * 100
      : (current > 0 ? 100 : 0);
    String changeDirection = mode == 'higherIsBetter'
      ? (change >= 0 ? 'positive' : 'negative')
      : (change <= 0 ? 'positive' : 'negative');

    return new Map<String, Object>{
      'key' => key,
      'label' => label,
      'value' => current,
      'previous' => previous,
      'change' => change.setScale(1),
      'changeDirection' => changeDirection,
      'format' => format
    };
  }

  private static String monthName(Integer m) {
    List<String> names = new List<String>{
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    };
    return names[m - 1];
  }

  // ═══════════════════════════════════════════════════════════
  // UPCOMING EVENTS — Next 30 days mixed events
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> getUpcomingEvents(Id accountId) {
    List<Map<String, Object>> events = new List<Map<String, Object>>();
    Date today = Date.today();
    Date in30Days = today.addDays(30);

    // 1. Contracts expiring soon
    for (Contract c : [
      SELECT Id, ContractNumber, EndDate, Status
      FROM Contract
      WHERE
        AccountId = :accountId
        AND Status = 'Activated'
        AND EndDate >= :today
        AND EndDate <= :in30Days
      ORDER BY EndDate ASC
      LIMIT 5
    ]) {
      Integer daysLeft = today.daysBetween(c.EndDate);
      String urgency = daysLeft <= 7 ? 'high' : 'normal';
      events.add(
        new Map<String, Object>{
          'type' => 'contract_expiry',
          'icon' => 'contract',
          'urgency' => urgency,
          'title' => 'Contract C-' +
          c.ContractNumber +
          ' expires',
          'subtitle' => 'In ' +
          daysLeft +
          ' day' +
          (daysLeft != 1 ? 's' : ''),
          'date' => c.EndDate,
          'sortDate' => c.EndDate,
          'url' => '/TalFlowExpress/s/my-contracts'
        }
      );
    }

    // 2. Quotes expiring soon
    for (Quote q : [
      SELECT Id, QuoteNumber, ExpirationDate, GrandTotal
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND B2B_Status__c = 'Sent to Customer'
        AND ExpirationDate != NULL
        AND ExpirationDate >= :today
        AND ExpirationDate <= :in30Days
      ORDER BY ExpirationDate ASC
      LIMIT 5
    ]) {
      Integer daysLeft = today.daysBetween(q.ExpirationDate);
      String urgency = daysLeft <= 3 ? 'high' : 'normal';
      Decimal amount = q.GrandTotal != null ? q.GrandTotal : 0;
      events.add(
        new Map<String, Object>{
          'type' => 'quote_expiry',
          'icon' => 'quote',
          'urgency' => urgency,
          'title' => 'Quote ' +
          q.QuoteNumber +
          ' expires',
          'subtitle' => 'In ' +
          daysLeft +
          ' day' +
          (daysLeft != 1 ? 's' : '') +
          ' · $' +
          amount.setScale(0).format(),
          'date' => q.ExpirationDate,
          'sortDate' => q.ExpirationDate,
          'url' => '/TalFlowExpress/s/my-quotes'
        }
      );
    }

    // 3. Orders pending or in progress (using EffectiveDate as proxy for "expected")
    for (Order o : [
      SELECT Id, OrderNumber, TotalAmount, Status, EffectiveDate
      FROM Order
      WHERE
        AccountId = :accountId
        AND Status IN ('Draft', 'Activated')
        AND EffectiveDate != NULL
        AND EffectiveDate >= :today
        AND EffectiveDate <= :in30Days
      ORDER BY EffectiveDate ASC
      LIMIT 5
    ]) {
      Integer daysLeft = today.daysBetween(o.EffectiveDate);
      Decimal amount = o.TotalAmount != null ? o.TotalAmount : 0;
      events.add(
        new Map<String, Object>{
          'type' => 'order_delivery',
          'icon' => 'order',
          'urgency' => 'normal',
          'title' => 'Order ' +
          o.OrderNumber +
          ' scheduled',
          'subtitle' => 'In ' +
          daysLeft +
          ' day' +
          (daysLeft != 1 ? 's' : '') +
          ' · $' +
          amount.setScale(0).format(),
          'date' => o.EffectiveDate,
          'sortDate' => o.EffectiveDate,
          'url' => '/TalFlowExpress/s/my-orders'
        }
      );
    }

    // Sort by date ASC and limit to 6
    events.sort(new UpcomingComparator());
    if (events.size() > 6) {
      List<Map<String, Object>> top6 = new List<Map<String, Object>>();
      for (Integer i = 0; i < 6; i++)
        top6.add(events[i]);
      return top6;
    }
    return events;
  }

  public class UpcomingComparator implements Comparator<Map<String, Object>> {
    public Integer compare(Map<String, Object> a, Map<String, Object> b) {
      Date da = (Date) a.get('sortDate');
      Date db = (Date) b.get('sortDate');
      if (da < db)
        return -1;
      if (da > db)
        return 1;
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION 7 DATA — Tier + Recommended (AI) + Upcoming
  // ═══════════════════════════════════════════════════════════

  public static Map<String, Object> getSection7Data() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      return new Map<String, Object>{
        'tier' => new Map<String, Object>(),
        'recommendedProducts' => new List<Map<String, Object>>(),
        'upcomingEvents' => new List<Map<String, Object>>(),
        'recommendationsAiPowered' => false
      };
    }

    Map<String, Object> heroStats = getHeroStats(accountId);
    Decimal ytdSpend = (Decimal) heroStats.get('ytdSpend');

    // Recommended products via AI (with fallback)
    List<Map<String, Object>> recommended;
    Boolean aiPowered = true;
    try {
      recommended = CkAgentforceInsightsService.generateRecommendedProducts(
        accountId
      );
      if (recommended == null || recommended.isEmpty()) {
        recommended = getFallbackRecommendations(accountId);
        aiPowered = false;
      }
    } catch (Exception e) {
      System.debug(
        'AI recommendations failed, using fallback: ' + e.getMessage()
      );
      recommended = getFallbackRecommendations(accountId);
      aiPowered = false;
    }

    return new Map<String, Object>{
      'tier' => getTierInfo(accountId, ytdSpend),
      'recommendedProducts' => recommended,
      'upcomingEvents' => getUpcomingEvents(accountId),
      'recommendationsAiPowered' => aiPowered
    };
  }

  private static List<Map<String, Object>> getFallbackRecommendations(
    Id accountId
  ) {
    Set<Id> purchasedIds = new Set<Id>();
    for (OrderItem oi : [
      SELECT Product2Id
      FROM OrderItem
      WHERE Order.AccountId = :accountId
    ]) {
      if (oi.Product2Id != null)
        purchasedIds.add(oi.Product2Id);
    }

    List<Map<String, Object>> fallback = new List<Map<String, Object>>();
    for (Product2 p : [
      SELECT
        Id,
        Name,
        Image_URL__c,
        B2B_Price__c,
        Rating__c,
        Product_Category__r.Name
      FROM Product2
      WHERE IsActive = TRUE AND B2B_Price__c != NULL AND Id NOT IN :purchasedIds
      ORDER BY Rating__c DESC NULLS LAST
      LIMIT 4
    ]) {
      fallback.add(
        new Map<String, Object>{
          'productId' => p.Id,
          'name' => p.Name,
          'imageUrl' => p.Image_URL__c,
          'price' => p.B2B_Price__c,
          'rating' => p.Rating__c != null ? p.Rating__c : 0,
          'category' => p.Product_Category__r != null
            ? p.Product_Category__r.Name
            : 'Other',
          'reason' => 'Highly rated product available for B2B'
        }
      );
    }
    return fallback;
  }
}
