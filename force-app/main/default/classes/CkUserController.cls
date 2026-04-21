public without sharing class CkUserController {

    @AuraEnabled(cacheable=true)
    public static UserDetails getUserDetails() {
        String userType = System.UserInfo.getUserType();
        
        if (userType == 'Guest' || userType == 'Standard' || userType == 'Admin') {
            UserDetails details = new UserDetails();
            details.isAuthenticated = false;
            return details;
        }

        User currentUser = [
            SELECT Id, FirstName, LastName, Email, SmallPhotoUrl, 
                   Profile.Name, Username, Phone, CompanyName,
                   CreatedDate, ContactId,
                   Contact.Profile_Photo_URL__c
            FROM User 
            WHERE Id = :System.UserInfo.getUserId()
            LIMIT 1
        ];

        UserDetails details = new UserDetails();
        details.isAuthenticated = true;
        details.userId = currentUser.Id;
        details.firstName = currentUser.FirstName;
        details.lastName = currentUser.LastName;
        details.fullName = currentUser.FirstName + ' ' + currentUser.LastName;
        details.email = currentUser.Email;
        details.phone = currentUser.Phone;
        details.photoUrl = currentUser.Contact.Profile_Photo_URL__c;
        details.profileName = currentUser.Profile.Name;
        details.companyName = currentUser.CompanyName;
        details.username = currentUser.Username;
        details.memberSince = currentUser.CreatedDate.format('MMMM yyyy');
        details.contactId = currentUser.ContactId;
        return details;
    }

    @AuraEnabled
    public static String uploadProfilePhoto(String fileName, String base64Data, String contactId) {
        try {
            // Créer le fichier
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.FirstPublishLocationId = contactId;
            insert cv;

            // Récupérer le ContentDocument
            ContentVersion insertedCv = [
                SELECT ContentDocumentId 
                FROM ContentVersion 
                WHERE Id = :cv.Id 
                LIMIT 1
            ];

            // Créer un lien public
            ContentDistribution cd = new ContentDistribution();
            cd.Name = fileName;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesAllowOriginalDownload = true;
            insert cd;

            // Récupérer l'URL publique
            ContentDistribution insertedCd = [
                SELECT DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution 
                WHERE Id = :cd.Id 
                LIMIT 1
            ];

            String photoUrl = insertedCd.ContentDownloadUrl;

            // Mettre à jour le Contact
            Contact c = new Contact(Id = contactId);
            c.Profile_Photo_URL__c = photoUrl;
            update c;

            return photoUrl;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class UserDetails {
        @AuraEnabled public Boolean isAuthenticated = false;
        @AuraEnabled public String userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String profileName;
        @AuraEnabled public String companyName;
        @AuraEnabled public String username;
        @AuraEnabled public String memberSince;
        @AuraEnabled public String contactId;
    }
}