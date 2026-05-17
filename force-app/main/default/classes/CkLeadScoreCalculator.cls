public without sharing class CkLeadScoreCalculator {

    @InvocableMethod(
        label='Calculate B2B Lead Score'
        description='Calcule le score de qualification du Lead B2B (0-100)'
    )
    public static List<LeadScoreResult> calculateLeadScore(List<Id> leadIds) {
        List<LeadScoreResult> results = new List<LeadScoreResult>();
        if (leadIds == null || leadIds.isEmpty()) return results;

        List<Lead> leads = [
            SELECT Id, Email, Website, Industry,
                   NumberOfEmployees, AnnualRevenue,
                   Phone, Description
            FROM Lead WHERE Id IN :leadIds
        ];

        List<Lead> toUpdate = new List<Lead>();
        for (Lead l : leads) {
            Integer score = calculateScore(l);
            l.Qualification_Score__c = score;
            toUpdate.add(l);

            LeadScoreResult r = new LeadScoreResult();
            r.leadId         = l.Id;
            r.score          = score;
            r.isQualified    = score >= 60;
            r.recommendation = score >= 60
                ? 'QUALIFY: Score ' + score + '/100. Call Qualify B2B Lead action.'
                : 'REJECT: Score ' + score + '/100. Call Reject B2B Lead action.';
            results.add(r);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        return results;
    }

    private static Integer calculateScore(Lead l) {
        Integer score = 0;
        if (String.isNotBlank(l.Email)
            && !l.Email.contains('gmail')
            && !l.Email.contains('yahoo')
            && !l.Email.contains('hotmail')) score += 20;
        if (String.isNotBlank(l.Website))                            score += 15;
        if (String.isNotBlank(l.Industry))                           score += 10;
        if (l.NumberOfEmployees != null && l.NumberOfEmployees > 10) score += 15;
        if (l.AnnualRevenue != null && l.AnnualRevenue > 100000)     score += 20;
        if (String.isNotBlank(l.Phone))                              score += 10;
        if (String.isNotBlank(l.Description))                        score += 10;
        return Math.min(score, 100);
    }

    public class LeadScoreResult {
        @InvocableVariable(label='Lead Id')
        public Id      leadId;
        @InvocableVariable(label='Qualification Score')
        public Integer score;
        @InvocableVariable(label='Is Qualified')
        public Boolean isQualified;
        @InvocableVariable(label='Recommendation')
        public String  recommendation;
    }
}