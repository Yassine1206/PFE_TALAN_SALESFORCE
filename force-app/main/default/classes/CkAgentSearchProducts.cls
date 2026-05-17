public without sharing class CkAgentSearchProducts {
  public class Input {
    @InvocableVariable(
      label='Search keyword'
      description='Keyword to search in product name or category (e.g., "laptop", "office")'
      required=true
    )
    public String keyword;
  }

  public class Output {
    @InvocableVariable(label='Products found')
    public String productsList;

    @InvocableVariable(label='Total products found')
    public Integer totalCount;
  }

  @InvocableMethod(
    label='Search Products in Catalog'
    description='Search active B2B products by keyword (matches name or category)'
    category='B2B Product Catalog'
  )
  public static List<Output> searchProducts(List<Input> inputs) {
    List<Output> results = new List<Output>();

    if (
      inputs == null ||
      inputs.isEmpty() ||
      String.isBlank(inputs[0].keyword)
    ) {
      Output out = new Output();
      out.productsList = 'No search keyword provided.';
      out.totalCount = 0;
      results.add(out);
      return results;
    }

    String keyword = inputs[0].keyword.trim();
    String likePattern = '%' + keyword + '%';

    List<Product2> products = [
      SELECT Id, Name, B2B_Price__c, Rating__c, Product_Category__r.Name
      FROM Product2
      WHERE
        IsActive = TRUE
        AND B2B_Price__c != NULL
        AND (Name LIKE :likePattern
        OR Product_Category__r.Name LIKE :likePattern)
      ORDER BY Rating__c DESC NULLS LAST
      LIMIT 5
    ];

    Output out = new Output();
    if (products.isEmpty()) {
      out.productsList =
        'No products found matching "' +
        keyword +
        '". Try different keywords or browse our catalog.';
      out.totalCount = 0;
    } else {
      String summary =
        'Found ' +
        products.size() +
        ' products matching "' +
        keyword +
        '":\n\n';
      for (Product2 p : products) {
        Decimal price = p.B2B_Price__c != null ? p.B2B_Price__c : 0;
        Decimal rating = p.Rating__c != null ? p.Rating__c : 0;
        String cat = p.Product_Category__r != null
          ? p.Product_Category__r.Name
          : 'Uncategorized';

        summary +=
          '• ' +
          p.Name +
          ' — $' +
          price.setScale(2).format() +
          ' — Category: ' +
          cat;
        if (rating > 0)
          summary += ' — Rating: ' + rating.setScale(1) + '/5';
        summary += '\n';
      }
      summary += '\nWould you like more details on any of these products?';
      out.productsList = summary;
      out.totalCount = products.size();
    }
    results.add(out);
    return results;
  }
}
