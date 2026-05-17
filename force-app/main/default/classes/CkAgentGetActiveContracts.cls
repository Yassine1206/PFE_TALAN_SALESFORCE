public without sharing class CkAgentGetActiveContracts {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;

    @InvocableVariable(
      label='Status filter (optional)'
      description='Filter contracts by status (e.g., Activated, Draft).'
      required=false
    )
    public String statusFilter;
  }

  public class Output {
    @InvocableVariable(label='Contracts summary')
    public String contractsSummary;

    @InvocableVariable(label='Total contracts count')
    public Integer totalCount;
  }

  @InvocableMethod(
    label='Get Customer Active Contracts'
    description='Returns the customer contracts with optional status filter'
    category='B2B Contract Management'
  )
  public static List<Output> getActiveContracts(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.contractsSummary = 'Unable to identify your account.';
      out.totalCount = 0;
      results.add(out);
      return results;
    }

    String statusFilter = 'Activated';
    if (
      inputs != null &&
      !inputs.isEmpty() &&
      String.isNotBlank(inputs[0].statusFilter)
    ) {
      statusFilter = inputs[0].statusFilter.trim();
    }

    List<Contract> contracts = [
      SELECT
        Id,
        ContractNumber,
        Status,
        StartDate,
        EndDate,
        ContractTerm,
        ActivatedDate
      FROM Contract
      WHERE AccountId = :accountId AND Status = :statusFilter
      ORDER BY EndDate ASC NULLS LAST
      LIMIT 10
    ];

    Output out = new Output();
    if (contracts.isEmpty()) {
      out.contractsSummary =
        'You have no contracts with status "' +
        statusFilter +
        '".';
      out.totalCount = 0;
    } else {
      String summary =
        'You have ' +
        contracts.size() +
        ' contract' +
        (contracts.size() > 1 ? 's' : '') +
        ' (' +
        statusFilter +
        '):\n\n';
      Date today = Date.today();

      for (Contract c : contracts) {
        String startStr = c.StartDate != null ? c.StartDate.format() : 'TBD';
        String endStr = c.EndDate != null ? c.EndDate.format() : 'TBD';
        String term = c.ContractTerm != null
          ? c.ContractTerm + ' months'
          : 'TBD';

        summary +=
          '• Contract C-' +
          c.ContractNumber +
          ' — Term: ' +
          term +
          ' — From ' +
          startStr +
          ' to ' +
          endStr;

        if (c.EndDate != null) {
          Integer daysLeft = today.daysBetween(c.EndDate);
          if (daysLeft < 0) {
            summary += ' ⚠️ EXPIRED';
          } else if (daysLeft <= 30) {
            summary +=
              ' ⚠️ Expires in ' +
              daysLeft +
              ' day' +
              (daysLeft != 1 ? 's' : '');
          }
        }
        summary += '\n';
      }
      out.contractsSummary = summary;
      out.totalCount = contracts.size();
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
