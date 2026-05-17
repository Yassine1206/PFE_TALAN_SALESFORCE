public with sharing class CkFooterController {
  @AuraEnabled(cacheable=true)
  public static FooterDataWrapper getFooterData() {
    FooterDataWrapper wrapper = new FooterDataWrapper();
    wrapper.brand = getBrandConfig();
    wrapper.shopLinks = getLinksBySection('Shop');
    wrapper.aboutLinks = getLinksBySection('About');
    wrapper.supportLinks = getLinksBySection('Support');
    return wrapper;
  }

  private static Footer_Brand_Config__mdt getBrandConfig() {
    List<Footer_Brand_Config__mdt> configs = [
      SELECT
        Tagline__c,
        Logo_Static_Resource_Name__c,
        Logo_Alt_Text__c,
        Copyright_Text__c,
        Instagram_URL__c,
        X_URL__c,
        Tiktok_URL__c,
        Privacy_Policy_URL__c,
        Terms_URL__c,
        Cookie_URL__c,
        Newsletter_Title__c,
        Newsletter_Description__c
      FROM Footer_Brand_Config__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    return configs.isEmpty() ? null : configs[0];
  }

  private static List<Footer_Link__c> getLinksBySection(String section) {
    return [
      SELECT Id, Label__c, URL__c, Open_In_New_Tab__c
      FROM Footer_Link__c
      WHERE Section__c = :section AND Is_Active__c = TRUE
      ORDER BY Sort_Order__c ASC NULLS LAST
    ];
  }

  public class FooterDataWrapper {
    @AuraEnabled
    public Footer_Brand_Config__mdt brand;
    @AuraEnabled
    public List<Footer_Link__c> shopLinks;
    @AuraEnabled
    public List<Footer_Link__c> aboutLinks;
    @AuraEnabled
    public List<Footer_Link__c> supportLinks;
  }
}
