public class CkB2BUserCreationJob implements Queueable {
    
    private String firstName;
    private String lastName;
    private String email;
    private String contactId;
    private String companyName;
    private String passwordHash;
    
    public CkB2BUserCreationJob(
        String firstName, String lastName, String email,
    String contactId, String companyName, String passwordHash
    ) {
        this.firstName   = firstName;
        this.lastName    = lastName;
        this.email       = email;
        this.contactId   = contactId;
        this.companyName = companyName;
        this.passwordHash = passwordHash;
    }
    
    public void execute(QueueableContext context) {
        try {
            List<Profile> profiles = [
                SELECT Id FROM Profile
                WHERE Name = 'Customer Community User' LIMIT 1
            ];
            if (profiles.isEmpty()) {
                profiles = [
                    SELECT Id FROM Profile
                    WHERE Name = 'External Identity User' LIMIT 1
                ];
            }
            if (profiles.isEmpty()) return;
            
            String alias = '';
            if (String.isNotBlank(firstName))
                alias += firstName.substring(0, 1);
            if (String.isNotBlank(lastName))
                alias += lastName.substring(0, Math.min(7, lastName.length()));
            
            User newUser              = new User();
            newUser.FirstName         = firstName;
            newUser.LastName          = lastName;
            newUser.Email             = email;
            newUser.Username          = email;
            newUser.ContactId         = Id.valueOf(contactId);
            newUser.ProfileId         = profiles[0].Id;
            newUser.Alias             = alias.toLowerCase();
            newUser.EmailEncodingKey  = 'UTF-8';
            newUser.LanguageLocaleKey = 'en_US';
            newUser.LocaleSidKey      = 'en_US';
            newUser.TimeZoneSidKey    = 'Africa/Tunis';
            newUser.CompanyName       = companyName;
            newUser.CommunityNickname = email.split('@')[0]
                + String.valueOf(Math.round(Math.random() * 9999));
            newUser.IsActive          = true;
            insert newUser;
            
            String password = EncodingUtil.base64Decode(passwordHash).toString();
            System.setPassword(newUser.Id, password);
            
            List<PermissionSet> ps = [
                SELECT Id FROM PermissionSet
                WHERE Name = 'Community_Customer_Access' LIMIT 1
            ];
            if (!ps.isEmpty()) {
                insert new PermissionSetAssignment(
                    PermissionSetId = ps[0].Id,
                AssigneeId      = newUser.Id
                    );
            }
            
            System.debug('B2B User created: ' + newUser.Id);
            
        } catch (Exception e) {
            System.debug('B2B User creation failed: ' + e.getMessage());
        }
    }
}