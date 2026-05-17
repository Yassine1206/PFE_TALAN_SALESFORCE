public without sharing class CkAgentGetContractsExpiringSoon {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Days threshold'
      description='Number of days to look ahead for expiring contracts (default 30)'
      required=false
    )
    public Integer daysAhead;
  }

  public class Output {
    @InvocableVariable(label='Expiring contracts summary')
    public String expiringSummary;

    @InvocableVariable(label='Total expiring contracts')
    public Integer totalCount;

    @InvocableVariable(label='Has urgent expirations (within 7 days)')
    public Boolean hasUrgent;
  }

  @InvocableMethod(
    label='Get Contracts Expiring Soon'
    description='Returns contracts expiring within the specified number of days (default 30 days)'
    category='B2B Contract Management'
  )
  public static List<Output> getContractsExpiringSoon(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.expiringSummary = 'Unable to identify your account.';
      out.totalCount = 0;
      out.hasUrgent = false;
      results.add(out);
      return results;
    }

    Integer daysAhead = 30;
    if (inputs != null && !inputs.isEmpty() && inputs[0].daysAhead != null) {
      daysAhead = Math.min(inputs[0].daysAhead, 365);
    }

    Date today = Date.today();
    Date endRange = today.addDays(daysAhead);

    List<Contract> contracts = [
      SELECT Id, ContractNumber, EndDate, ContractTerm, StartDate
      FROM Contract
      WHERE
        AccountId = :accountId
        AND Status = 'Activated'
        AND EndDate >= :today
        AND EndDate <= :endRange
      ORDER BY EndDate ASC
      LIMIT 10
    ];

    Output out = new Output();
    Boolean urgent = false;

    if (contracts.isEmpty()) {
      out.expiringSummary =
        'Good news! You have no contracts expiring within the next ' +
        daysAhead +
        ' days.';
      out.totalCount = 0;
      out.hasUrgent = false;
    } else {
      String summary =
        'You have ' +
        contracts.size() +
        ' contract' +
        (contracts.size() > 1 ? 's' : '') +
        ' expiring within ' +
        daysAhead +
        ' days:\n\n';

      for (Contract c : contracts) {
        Integer daysLeft = today.daysBetween(c.EndDate);
        if (daysLeft <= 7)
          urgent = true;

        String urgencyMarker = '';
        if (daysLeft <= 7)
          urgencyMarker = '🔴 URGENT — ';
        else if (daysLeft <= 14)
          urgencyMarker = '🟠 ';

        summary +=
          '• ' +
          urgencyMarker +
          'Contract C-' +
          c.ContractNumber +
          ' expires on ' +
          c.EndDate.format() +
          ' (in ' +
          daysLeft +
          ' day' +
          (daysLeft != 1 ? 's' : '') +
          ')\n';
      }

      summary += '\nWe recommend initiating renewal discussions soon. ';
      summary += 'Contact your account manager to renew or extend your contract.';

      out.expiringSummary = summary;
      out.totalCount = contracts.size();
      out.hasUrgent = urgent;
    }
    results.add(out);
    return results;
  }

  private static Id resolveAccountId(String contactIdStr) {
    Id contactId = null;
    if (String.isNotBlank(contactIdStr)) {
      try {
        contactId = (Id) contactIdStr;
      } catch (Exception e) {
        System.debug('Invalid contactId string: ' + contactIdStr);
      }
    }
    if (contactId != null) {
      try {
        Contact c = [
          SELECT Id, AccountId
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        return c.AccountId;
      } catch (Exception e) {
        System.debug('Contact lookup failed: ' + e.getMessage());
      }
    }
    return null;
  }
}
