public with sharing class CkHeroController {
  @AuraEnabled(cacheable=true)
  public static HeroSlide__c getActiveHero() {
    List<HeroSlide__c> slides = [
      SELECT
        Id,
        Name,
        Badge_Text__c,
        Title__c,
        Subtitle__c,
        Background_Image_Url__c,
        Primary_Button_Label__c,
        Primary_Button_Url__c,
        Secondary_Button_Label__c,
        Secondary_Button_Url__c
      FROM HeroSlide__c
      WHERE Is_Active__c = TRUE
      ORDER BY Display_Order__c ASC NULLS LAST, LastModifiedDate DESC
      LIMIT 1
    ];

    return slides.isEmpty() ? null : slides[0];
  }
}
