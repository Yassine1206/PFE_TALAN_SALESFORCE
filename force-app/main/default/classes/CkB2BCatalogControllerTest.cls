@isTest
private class CkB2BCatalogControllerTest {
  // ═══════════════════════════════════════════════════════════
  // TEST DATA SETUP
  // ═══════════════════════════════════════════════════════════

  @TestSetup
  static void setupTestData() {
    // Create B2B Account
    Account acc = new Account(
      Name = 'Test B2B Catalog Corp',
      Account_Type__c = 'B2B'
    );
    insert acc;

    // Create Contact
    Contact con = new Contact(
      FirstName = 'Cat',
      LastName = 'Tester',
      Email = 'cattester@talflow.test',
      AccountId = acc.Id,
      Is_Email_Verified__c = true
    );
    insert con;

    // Create Community User
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Customer Community User'
      LIMIT 1
    ];

    User u = new User(
      Username = 'catcontroller' + System.currentTimeMillis() + '@talflow.test',
      Email = 'cattester@talflow.test',
      FirstName = 'Cat',
      LastName = 'Tester',
      Alias = 'cat',
      TimeZoneSidKey = 'Africa/Tunis',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id,
      ContactId = con.Id
    );
    insert u;

    // Create Product Category
    Product_Category__c cat = new Product_Category__c(
      Name = 'Test Audio Category'
    );
    insert cat;

    // Create 3 Products
    List<Product2> products = new List<Product2>{
      new Product2(
        Name = 'Test Speaker Premium',
        IsActive = true,
        B2B_Price__c = 100,
        Stock_Quantity__c = 50,
        Rating__c = 4.5,
        Is_On_Sale__c = true,
        Image_URL__c = 'https://example.com/speaker.jpg',
        Product_Category__c = cat.Id
      ),
      new Product2(
        Name = 'Test Headphones Pro',
        IsActive = true,
        B2B_Price__c = 200,
        Stock_Quantity__c = 0,
        Rating__c = 3.5,
        Is_On_Sale__c = false,
        Image_URL__c = 'https://example.com/headphones.jpg',
        Product_Category__c = cat.Id
      ),
      new Product2(
        Name = 'Test Microphone Studio',
        IsActive = true,
        B2B_Price__c = 350,
        Stock_Quantity__c = 25,
        Rating__c = 4.8,
        Is_On_Sale__c = false,
        Image_URL__c = 'https://example.com/microphone.jpg',
        Product_Category__c = cat.Id
      )
    };
    insert products;

    // Get Standard Pricebook
    Pricebook2 standardPb = new Pricebook2(
      Id = Test.getStandardPricebookId(),
      IsActive = true
    );
    update standardPb;

    // Create PricebookEntries (retail prices)
    List<PricebookEntry> pbes = new List<PricebookEntry>();
    for (Product2 prod : products) {
      pbes.add(
        new PricebookEntry(
          Pricebook2Id = standardPb.Id,
          Product2Id = prod.Id,
          UnitPrice = prod.B2B_Price__c * 1.18, // ~retail = B2B + 18%
          IsActive = true
        )
      );
    }
    insert pbes;
  }

  // ═══════════════════════════════════════════════════════════
  // TESTS — getProducts
  // ═══════════════════════════════════════════════════════════

  @isTest
  static void testGetProductsWithoutFilter() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(3, products.size(), 'Should return 3 B2B products');
  }

  @isTest
  static void testGetProductsWithSearchTerm() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    filters.searchTerm = 'Speaker';
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(1, products.size(), 'Should match only Speaker');
    System.assert(
      products[0].name.contains('Speaker'),
      'Name should contain Speaker'
    );
  }

  @isTest
  static void testGetProductsInStockOnly() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    filters.inStockOnly = true;
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(
      2,
      products.size(),
      'Should exclude out-of-stock product'
    );
  }

  @isTest
  static void testGetProductsOnSaleOnly() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    filters.onSaleOnly = true;
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(
      1,
      products.size(),
      'Should return only the on-sale product'
    );
  }

  @isTest
  static void testGetProductsTopRatedOnly() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    filters.topRatedOnly = true;
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(
      2,
      products.size(),
      'Should return only products with rating >= 4'
    );
  }

  @isTest
  static void testGetProductsPriceRange() {
    Test.startTest();
    CkB2BCatalogController.FilterParams filters = new CkB2BCatalogController.FilterParams();
    filters.minPrice = 150;
    filters.maxPrice = 250;
    List<CkB2BCatalogController.B2BProduct> products = CkB2BCatalogController.getProducts(
      filters
    );
    Test.stopTest();

    System.assertEquals(
      1,
      products.size(),
      'Should return only Headphones at $200'
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TESTS — getCategories
  // ═══════════════════════════════════════════════════════════

  @isTest
  static void testGetCategories() {
    Test.startTest();
    List<CkB2BCatalogController.CategoryOption> cats = CkB2BCatalogController.getCategories();
    Test.stopTest();

    System.assertEquals(
      1,
      cats.size(),
      'Should return 1 category with B2B products'
    );
    System.assertEquals(
      3,
      cats[0].productCount,
      'Category should have 3 products'
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TESTS — submitQuickQuote
  // ═══════════════════════════════════════════════════════════

  @isTest
  static void testSubmitQuickQuoteSuccess() {
    User b2bUser = [SELECT Id FROM User WHERE LastName = 'Tester' LIMIT 1];
    Product2 product = [
      SELECT Id
      FROM Product2
      WHERE Name = 'Test Speaker Premium'
      LIMIT 1
    ];

    Test.startTest();
    System.runAs(b2bUser) {
      String quoteId = CkB2BCatalogController.submitQuickQuote(
        product.Id,
        10,
        Date.today().addDays(15),
        'Need quick delivery'
      );

      System.assertNotEquals(null, quoteId, 'Quote ID should be returned');

      // Verify Quote was created
      Quote q = [
        SELECT Id, B2B_Status__c, Special_Terms__c, Requested_Delivery_Date__c
        FROM Quote
        WHERE Id = :quoteId
        LIMIT 1
      ];
      System.assertEquals(
        'Draft',
        q.B2B_Status__c,
        'New quote should be Draft'
      );
      System.assertEquals('Need quick delivery', q.Special_Terms__c);

      // Verify QuoteLineItem was created
      List<QuoteLineItem> qlis = [
        SELECT Id, Quantity
        FROM QuoteLineItem
        WHERE QuoteId = :quoteId
      ];
      System.assertEquals(1, qlis.size(), 'Should have 1 line item');
      System.assertEquals(10, qlis[0].Quantity);
    }
    Test.stopTest();
  }

  @isTest
  static void testSubmitQuickQuoteInvalidQuantity() {
    User b2bUser = [SELECT Id FROM User WHERE LastName = 'Tester' LIMIT 1];
    Product2 product = [
      SELECT Id
      FROM Product2
      WHERE Name = 'Test Speaker Premium'
      LIMIT 1
    ];

    Boolean exceptionThrown = false;

    Test.startTest();
    System.runAs(b2bUser) {
      try {
        CkB2BCatalogController.submitQuickQuote(
          product.Id,
          0,
          Date.today().addDays(15),
          null
        );
      } catch (Exception e) {
        exceptionThrown = true;
      }
    }
    Test.stopTest();

    System.assert(
      exceptionThrown,
      'An exception should be thrown for invalid quantity'
    );
  }

  @isTest
  static void testSubmitQuickQuoteInvalidProduct() {
    User b2bUser = [SELECT Id FROM User WHERE LastName = 'Tester' LIMIT 1];

    Boolean exceptionThrown = false;

    Test.startTest();
    System.runAs(b2bUser) {
      try {
        CkB2BCatalogController.submitQuickQuote(
          null,
          5,
          Date.today().addDays(15),
          null
        );
      } catch (Exception e) {
        exceptionThrown = true;
      }
    }
    Test.stopTest();

    System.assert(
      exceptionThrown,
      'An exception should be thrown for null product'
    );
  }
}
