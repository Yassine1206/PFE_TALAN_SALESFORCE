/**
 * @description Controller for managing user theme preferences (light/dark mode).
 * @author      TalFlow Express
 */
public without sharing class CkThemeController {
  @AuraEnabled(cacheable=true)
  public static String getThemePreference() {
    try {
      User u = [
        SELECT Id, Theme_Preference__c
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      return u.Theme_Preference__c != null ? u.Theme_Preference__c : 'Light';
    } catch (Exception e) {
      return 'Light';
    }
  }

  @AuraEnabled
  public static void setThemePreference(String theme) {
    if (theme != 'Light' && theme != 'Dark') {
      throw new AuraHandledException('Invalid theme value');
    }
    try {
      User u = new User(Id = UserInfo.getUserId(), Theme_Preference__c = theme);
      update u;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to update theme preference: ' + e.getMessage()
      );
    }
  }
}
