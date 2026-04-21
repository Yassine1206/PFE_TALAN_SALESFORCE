global class SocialRegHandler implements Auth.RegistrationHandler {
    
    global User createUser(Id portalId, Auth.UserData data) {
        // Chercher si l'utilisateur existe déjà
        List<User> existingUsers = [
            SELECT Id, ContactId FROM User 
            WHERE Email = :data.email 
            AND IsActive = true 
            LIMIT 1
        ];
        
        if (!existingUsers.isEmpty()) {
            // Mettre à jour la photo si elle existe
            if (String.isNotBlank(data.attributeMap.get('picture'))) {
                updateContactPhoto(existingUsers[0].ContactId, data.attributeMap.get('picture'));
            }
            return existingUsers[0];
        }
        
        // Créer ou récupérer l'Account
        Account acc = getOrCreateAccount('TalFlow Social Customers');
        
        // Créer le Contact avec la photo
        Contact c = new Contact();
        c.FirstName = data.firstName;
        c.LastName = data.lastName;
        c.Email = data.email;
        c.AccountId = acc.Id;
        c.LeadSource = 'Social';
        c.Description = 'Registered via ' + data.provider;
        
        // Sauvegarder la photo Google/Facebook
        String photoUrl = '';
        if (data.attributeMap != null) {
            if (data.attributeMap.containsKey('picture')) {
                photoUrl = data.attributeMap.get('picture');
            } else if (data.attributeMap.containsKey('profile_image_url')) {
                photoUrl = data.attributeMap.get('profile_image_url');
            }
        }
        if (String.isNotBlank(photoUrl)) {
            c.Profile_Photo_URL__c = photoUrl;
        }
        
        insert c;
        
        // Créer le User
        Profile p = [SELECT Id FROM Profile WHERE Name = 'External Identity User' LIMIT 1];
        
        String alias = '';
        if (String.isNotBlank(data.firstName)) {
            alias += data.firstName.substring(0, Math.min(data.firstName.length(), 1));
        }
        if (String.isNotBlank(data.lastName)) {
            alias += data.lastName.substring(0, Math.min(data.lastName.length(), 7));
        }
        
        User u = new User();
        u.FirstName = data.firstName;
        u.LastName = data.lastName;
        u.Email = data.email;
        u.Username = data.email + '.talflow';
        u.ContactId = c.Id;
        u.ProfileId = p.Id;
        u.Alias = alias.toLowerCase();
        u.EmailEncodingKey = 'UTF-8';
        u.LanguageLocaleKey = 'en_US';
        u.LocaleSidKey = 'en_US';
        u.TimeZoneSidKey = 'America/New_York';
        u.CommunityNickname = data.email.split('@')[0] + String.valueOf(Math.round(Math.random() * 9999));
        u.IsActive = true;
        
        return u;
    }
    
    global void updateUser(Id userId, Id portalId, Auth.UserData data) {
        User u = [
        SELECT Id, FirstName, LastName, Email, ContactId
        FROM User WHERE Id = :userId LIMIT 1
    ];
        u.FirstName = data.firstName;
        u.LastName  = data.lastName;
        u.Email     = data.email;
        update u;
        
        // Récupérer la photo Google/Facebook
        String googlePhoto = '';
        if (data.attributeMap != null) {
            if (data.attributeMap.containsKey('picture')) {
                googlePhoto = data.attributeMap.get('picture');
            } else if (data.attributeMap.containsKey('profile_image_url')) {
                googlePhoto = data.attributeMap.get('profile_image_url');
            }
        }
        
        // FIX : ne mettre à jour la photo que si pas de photo custom
        if (String.isNotBlank(googlePhoto) && u.ContactId != null) {
            List<Contact> cons = [
            SELECT Id, Profile_Photo_URL__c
            FROM Contact WHERE Id = :u.ContactId LIMIT 1
        ];
            if (!cons.isEmpty()) {
                String currentPhoto  = cons[0].Profile_Photo_URL__c;
                Boolean isEmpty      = String.isBlank(currentPhoto);
                Boolean isGooglePhoto = String.isNotBlank(currentPhoto)
                    && currentPhoto.contains('googleusercontent.com');
                Boolean isFacebookPhoto = String.isNotBlank(currentPhoto)
                    && currentPhoto.contains('fbsbx.com');
                
                // Écraser seulement si vide ou déjà une photo sociale
                if (isEmpty || isGooglePhoto || isFacebookPhoto) {
                    updateContactPhoto(u.ContactId, googlePhoto);
                }
                // Si photo custom → ne pas écraser
            }
        }
        
        // Auto-assign Permission Set
        assignPermissionSet(userId);
    }
    
    private void updateContactPhoto(Id contactId, String photoUrl) {
        if (contactId == null || String.isBlank(photoUrl)) return;
        Contact c = new Contact(Id = contactId);
        c.Profile_Photo_URL__c = photoUrl;
        update c;
    }
    
    private Account getOrCreateAccount(String accountName) {
        List<Account> existing = [SELECT Id FROM Account WHERE Name = :accountName LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        Account acc = new Account(Name = accountName);
        insert acc;
        return acc;
    }
    private void assignPermissionSet(Id userId) {
        try {
            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment 
                WHERE AssigneeId = :userId 
                AND PermissionSet.Name = 'Community_Cart_Access'
                LIMIT 1
            ];
            
            if (existing.isEmpty()) {
                PermissionSet ps = [
                    SELECT Id FROM PermissionSet 
                    WHERE Name = 'Community_Cart_Access' 
                    LIMIT 1
                ];
                insert new PermissionSetAssignment(
                    AssigneeId = userId,
                PermissionSetId = ps.Id
                    );
            }
        } catch (Exception e) {
            System.debug('Permission Set assignment failed: ' + e.getMessage());
        }
    }
}