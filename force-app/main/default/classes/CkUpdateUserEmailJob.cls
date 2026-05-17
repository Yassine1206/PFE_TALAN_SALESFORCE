public class CkUpdateUserEmailJob implements Queueable, Database.AllowsCallouts {
    
    private String userId;
    private String newEmail;
    
    public CkUpdateUserEmailJob(String userId, String newEmail) {
        this.userId   = userId;
        this.newEmail = newEmail;
    }
    
    public void execute(QueueableContext context) {
        try {
            String newUsername = newEmail + '.talflow';
            
            List<User> existing = [
                SELECT Id FROM User
                WHERE Username = :newUsername
                AND Id != :userId LIMIT 1
            ];
            if (!existing.isEmpty()) {
                newUsername = newEmail + '.talflow'
                    + String.valueOf(Math.round(Math.random() * 999));
            }
            
            String body = JSON.serialize(new Map<String, Object>{
                'Email'             => newEmail,
                'Username'          => newUsername,
                'CommunityNickname' => newEmail.split('@')[0]
                    + String.valueOf(Math.round(Math.random() * 9999))
            });
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                'callout:Salesforce_Internal_API/services/data/v59.0/sobjects/User/'
                + userId
                );
            req.setMethod('PATCH');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
            req.setTimeout(10000);
            
            HttpResponse res = new Http().send(req);
            // Dans execute() du Queueable, après le callout :
            
            System.debug('=== CALLOUT RESULT ===');
            System.debug('Status Code: ' + res.getStatusCode());
            System.debug('Status: '      + res.getStatus());
            System.debug('Body: '        + res.getBody());
            System.debug('Headers: '     + res.getHeader('Content-Type'));
            System.debug('=== END ===');
            
            System.debug('Status: ' + res.getStatusCode());
            System.debug('Body: '   + res.getBody());
            
            if (res.getStatusCode() == 204) {
                System.debug('Email updated: ' + newEmail);
            } else {
                System.debug('Failed: ' + res.getBody());
            }
            
        } catch (Exception e) {
            System.debug('FAILED: ' + e.getMessage());
            System.debug('STACK: '  + e.getStackTraceString());
        }
    }
}