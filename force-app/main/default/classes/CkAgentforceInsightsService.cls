public without sharing class CkAgentforceInsightsService {
  public static List<Map<String, Object>> generateInsights(Id accountId) {
    // 1. Build the customer JSON payload
    String accountDataJson = buildAccountDataJson(accountId);

    // 2. Call the Prompt Template via ConnectApi
    String llmResponse = callPromptTemplate(accountDataJson);

    // 3. Parse the JSON response from the LLM
    return parseInsightsResponse(llmResponse);
  }

  // ═══════════════════════════════════════════════════════════
  // STEP 1 — BUILD CUSTOMER DATA
  // ═══════════════════════════════════════════════════════════

  private static String buildAccountDataJson(Id accountId) {
    // Get account info
    Account acc = CkB2BDashboardService.getAccountInfo(accountId);

    // Get hero stats (YTD spend, pending quotes, active contracts)
    Map<String, Object> hero = CkB2BDashboardService.getHeroStats(accountId);
    Decimal ytdSpend = (Decimal) hero.get('ytdSpend');

    // Get tier info
    Map<String, Object> tierInfo = CkB2BDashboardService.getTierInfo(
      accountId,
      ytdSpend
    );

    // Count expiring contracts
    Integer expiring30d = [
      SELECT COUNT()
      FROM Contract
      WHERE
        AccountId = :accountId
        AND Status = 'Activated'
        AND EndDate <= :Date.today().addDays(30)
        AND EndDate >= :Date.today()
    ];

    // Quotes this month
    Integer quotesThisMonth = [
      SELECT COUNT()
      FROM Quote
      WHERE
        Opportunity.AccountId = :accountId
        AND CreatedDate >= :Date.today().toStartOfMonth()
    ];

    // Months as a member
    Integer memberSinceMonths = acc != null
      ? Math.abs(Date.today().monthsBetween(acc.CreatedDate.date()))
      : 0;

    // Build the data map
    Map<String, Object> payload = new Map<String, Object>{
      'accountName' => acc != null ? acc.Name : 'Unknown',
      'tier' => tierInfo.get('currentTier'),
      'ytdSpend' => ytdSpend,
      'pendingQuotes' => hero.get('pendingQuotes'),
      'activeContracts' => hero.get('activeContracts'),
      'contractsExpiring30d' => expiring30d,
      'quotesThisMonth' => quotesThisMonth,
      'memberSinceMonths' => memberSinceMonths,
      'industry' => acc != null &&
        acc.Industry != null
        ? acc.Industry
        : 'Unknown'
    };

    return JSON.serialize(payload);
  }

  // ═══════════════════════════════════════════════════════════
  // STEP 2 — CALL PROMPT TEMPLATE VIA CONNECT API
  // ═══════════════════════════════════════════════════════════

  /* ═══════════════════════════════════════════════════════════
   PATCH APEX — REMPLACE callPromptTemplate() dans CkAgentforceInsightsService.cls
   
   Améliorations :
   - Affiche le message d'erreur précis si l'API échoue
   - Loggue la réponse complète pour debug
   - Change applicationName 'PromptBuilderPreview' → 'PromptTemplateGenerationsInvocable'
   ═══════════════════════════════════════════════════════════ */

  private static String callPromptTemplate(String accountDataJson) {
    try {
      // Build the input map for the prompt template
      ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
      inputValue.value = accountDataJson;

      Map<String, ConnectApi.WrappedValue> inputs = new Map<String, ConnectApi.WrappedValue>();
      inputs.put('Input:accountData', inputValue);
      // Build the input request
      ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
      input.isPreview = false;
      input.inputParams = inputs;

      // The API name of the Prompt Template
      String templateApiName = 'TalFlow_B2B_Insights';

      System.debug('🤖 Calling Einstein LLM with template: ' + templateApiName);
      System.debug('🤖 Input data: ' + accountDataJson);

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generations = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
        templateApiName,
        input
      );

      // ─── DEBUG: Log everything from the response ───
      System.debug('🤖 Raw response: ' + JSON.serialize(generations));

      if (generations == null) {
        System.debug('❌ Generations object is NULL');
        return null;
      }

      // Check if there's an error
      if (
        generations.generationErrors != null &&
        !generations.generationErrors.isEmpty()
      ) {
        for (
          ConnectApi.EinsteinPromptTemplateGenerationsError err : generations.generationErrors
        ) {
          System.debug('❌ LLM Error: ' + JSON.serialize(err));
        }
      }

      // Extract the response
      if (
        generations.generations != null && !generations.generations.isEmpty()
      ) {
        String text = generations.generations[0].text;
        System.debug('✓ LLM returned text (' + text.length() + ' chars):');
        System.debug(text);
        return text;
      }

      System.debug('⚠️ No generations returned in response');
      return null;
    } catch (Exception e) {
      System.debug(
        '❌ Exception in callPromptTemplate: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
      System.debug('Stack: ' + e.getStackTraceString());
      throw new AuraHandledException('AI generation failed: ' + e.getMessage());
    }
  }

  // ═══════════════════════════════════════════════════════════
  // STEP 3 — PARSE LLM RESPONSE
  // ═══════════════════════════════════════════════════════════

  private static List<Map<String, Object>> parseInsightsResponse(
    String llmResponse
  ) {
    if (String.isBlank(llmResponse))
      return new List<Map<String, Object>>();

    // Clean potential markdown code blocks (some LLMs wrap JSON in ```json ... ```)
    String cleaned = llmResponse.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();
    }

    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        cleaned
      );
      List<Object> rawInsights = (List<Object>) parsed.get('insights');

      List<Map<String, Object>> result = new List<Map<String, Object>>();
      if (rawInsights != null) {
        for (Object o : rawInsights) {
          Map<String, Object> ins = (Map<String, Object>) o;
          // Add color based on icon for the LWC styling
          String icon = (String) ins.get('icon');
          String color = '#FF6B1A';
          if (icon == 'alert')
            color = '#E24B4A';
          else if (icon == 'trending-up')
            color = '#1D9E75';
          else if (icon == 'trophy')
            color = '#FF6B1A';
          else if (icon == 'trending-down')
            color = '#E24B4A';
          ins.put('color', color);
          result.add(ins);
        }
      }
      return result;
    } catch (Exception e) {
      System.debug('Parse error: ' + e.getMessage() + ' | Raw: ' + llmResponse);
      return new List<Map<String, Object>>();
    }
  }
  // ═══════════════════════════════════════════════════════════
  // RECOMMENDED PRODUCTS — AI-powered suggestions
  // ═══════════════════════════════════════════════════════════

  public static List<Map<String, Object>> generateRecommendedProducts(
    Id accountId
  ) {
    // 1. Build the customer + catalog payload
    String customerDataJson = buildRecommendationDataJson(accountId);

    // 2. Call the Recommendations Prompt Template
    String llmResponse = callRecommendationTemplate(customerDataJson);

    // 3. Parse the JSON response
    List<Map<String, Object>> recommendations = parseRecommendationsResponse(
      llmResponse
    );

    // 4. Hydrate with product details from Salesforce
    return hydrateProductDetails(recommendations);
  }

  private static String buildRecommendationDataJson(Id accountId) {
    Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);

    // Top 5 categories purchased
    AggregateResult[] catResults = [
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
    List<String> topCategories = new List<String>();
    for (AggregateResult r : catResults) {
      String cat = (String) r.get('catName');
      if (String.isNotBlank(cat))
        topCategories.add(cat);
    }

    // Already purchased product IDs
    Set<Id> purchasedIds = new Set<Id>();
    for (OrderItem oi : [
      SELECT Product2Id
      FROM OrderItem
      WHERE Order.AccountId = :accountId
    ]) {
      if (oi.Product2Id != null)
        purchasedIds.add(oi.Product2Id);
    }

    // Available B2B products (not yet purchased) — TOP 50
    List<Map<String, Object>> availableProducts = new List<Map<String, Object>>();
    for (Product2 p : [
      SELECT Id, Name, B2B_Price__c, Product_Category__r.Name, Rating__c
      FROM Product2
      WHERE IsActive = TRUE AND B2B_Price__c != NULL AND Id NOT IN :purchasedIds
      ORDER BY Rating__c DESC NULLS LAST
      LIMIT 50
    ]) {
      availableProducts.add(
        new Map<String, Object>{
          'productId' => p.Id,
          'name' => p.Name,
          'category' => p.Product_Category__r != null
            ? p.Product_Category__r.Name
            : 'Other',
          'price' => p.B2B_Price__c,
          'rating' => p.Rating__c != null ? p.Rating__c : 0
        }
      );
    }

    // Customer info
    Account acc = CkB2BDashboardService.getAccountInfo(accountId);
    Map<String, Object> hero = CkB2BDashboardService.getHeroStats(accountId);
    Decimal ytdSpend = (Decimal) hero.get('ytdSpend');
    Map<String, Object> tierInfo = CkB2BDashboardService.getTierInfo(
      accountId,
      ytdSpend
    );

    Map<String, Object> payload = new Map<String, Object>{
      'accountName' => acc != null ? acc.Name : 'Unknown',
      'industry' => acc != null &&
        acc.Industry != null
        ? acc.Industry
        : 'Unknown',
      'tier' => tierInfo.get('currentTier'),
      'topCategories' => topCategories,
      'alreadyPurchasedCount' => purchasedIds.size(),
      'availableProducts' => availableProducts
    };

    return JSON.serialize(payload);
  }

  private static String callRecommendationTemplate(String customerDataJson) {
    try {
      ConnectApi.WrappedValue inputValue = new ConnectApi.WrappedValue();
      inputValue.value = customerDataJson;

      Map<String, ConnectApi.WrappedValue> inputs = new Map<String, ConnectApi.WrappedValue>();
      inputs.put('Input:customerData', inputValue);

      ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
      input.isPreview = false;
      input.inputParams = inputs;

      String templateApiName = 'TalFlow_Product_Recommendations';
      System.debug('🤖 Calling Recommendations template');

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generations = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
        templateApiName,
        input
      );

      if (
        generations != null &&
        generations.generations != null &&
        !generations.generations.isEmpty()
      ) {
        String text = generations.generations[0].text;
        System.debug('✓ Recommendations LLM returned: ' + text);
        return text;
      }
      return null;
    } catch (Exception e) {
      System.debug('❌ Recommendations error: ' + e.getMessage());
      return null;
    }
  }

  private static List<Map<String, Object>> parseRecommendationsResponse(
    String llmResponse
  ) {
    if (String.isBlank(llmResponse))
      return new List<Map<String, Object>>();

    String cleaned = llmResponse.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();
    }

    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        cleaned
      );
      List<Object> rawRecs = (List<Object>) parsed.get('recommendations');

      List<Map<String, Object>> result = new List<Map<String, Object>>();
      if (rawRecs != null) {
        for (Object o : rawRecs) {
          result.add((Map<String, Object>) o);
        }
      }
      return result;
    } catch (Exception e) {
      System.debug('Parse error: ' + e.getMessage());
      return new List<Map<String, Object>>();
    }
  }

  private static List<Map<String, Object>> hydrateProductDetails(
    List<Map<String, Object>> recommendations
  ) {
    if (recommendations.isEmpty())
      return recommendations;

    // Collect product IDs
    Set<Id> productIds = new Set<Id>();
    Map<Id, String> reasonByProductId = new Map<Id, String>();
    for (Map<String, Object> rec : recommendations) {
      String pidStr = (String) rec.get('productId');
      if (String.isNotBlank(pidStr)) {
        try {
          Id pid = (Id) pidStr;
          productIds.add(pid);
          reasonByProductId.put(pid, (String) rec.get('reason'));
        } catch (Exception e) {
          System.debug('Invalid product ID: ' + pidStr);
        }
      }
    }

    // Fetch product details
    Map<Id, Product2> productMap = new Map<Id, Product2>(
      [
        SELECT
          Id,
          Name,
          Image_URL__c,
          B2B_Price__c,
          Rating__c,
          Product_Category__r.Name
        FROM Product2
        WHERE Id IN :productIds
      ]
    );

    // Build final list with hydrated details
    List<Map<String, Object>> hydrated = new List<Map<String, Object>>();
    for (Map<String, Object> rec : recommendations) {
      Id pid;
      try {
        pid = (Id) rec.get('productId');
      } catch (Exception e) {
        continue;
      }
      Product2 p = productMap.get(pid);
      if (p == null)
        continue;

      hydrated.add(
        new Map<String, Object>{
          'productId' => p.Id,
          'name' => p.Name,
          'imageUrl' => p.Image_URL__c,
          'price' => p.B2B_Price__c != null ? p.B2B_Price__c : 0,
          'rating' => p.Rating__c != null ? p.Rating__c : 0,
          'category' => p.Product_Category__r != null
            ? p.Product_Category__r.Name
            : 'Other',
          'reason' => reasonByProductId.get(p.Id)
        }
      );
    }
    return hydrated;
  }
}
