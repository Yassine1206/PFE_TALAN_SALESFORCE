public without sharing class CkAgentGetMyTierBenefits {
  public class Input {
    @InvocableVariable(
      label='Contact ID of the verified customer'
      description='The Contact ID of the customer (from VerifiedCustomerId).'
      required=false
    )
    public String contactId;
  }

  public class Output {
    @InvocableVariable(label='Tier and benefits info')
    public String tierInfo;

    @InvocableVariable(label='Current tier name')
    public String currentTier;

    @InvocableVariable(label='YTD spend')
    public Decimal ytdSpend;
  }

  @InvocableMethod(
    label='Get My Tier Benefits'
    description='Returns the customer current tier (Bronze/Silver/Gold/Platinum) with its benefits and progression to next tier'
    category='B2B General Support'
  )
  public static List<Output> getMyTierBenefits(List<Input> inputs) {
    List<Output> results = new List<Output>();

    String contactId = inputs != null && !inputs.isEmpty()
      ? inputs[0].contactId
      : null;
    Id accountId = resolveAccountId(contactId);

    if (accountId == null) {
      Output out = new Output();
      out.tierInfo = 'Unable to identify your account.';
      out.currentTier = 'Unknown';
      out.ytdSpend = 0;
      results.add(out);
      return results;
    }

    AggregateResult[] ytdResult = [
      SELECT SUM(TotalAmount) total
      FROM Order
      WHERE
        AccountId = :accountId
        AND CALENDAR_YEAR(EffectiveDate) = :Date.today().year()
    ];
    Decimal ytdSpend = ytdResult.isEmpty() || ytdResult[0].get('total') == null
      ? 0
      : (Decimal) ytdResult[0].get('total');

    String tier;
    Decimal nextLimit;
    String nextTier;
    List<String> benefits = new List<String>();

    if (ytdSpend < 5000) {
      tier = 'Bronze';
      nextTier = 'Silver';
      nextLimit = 5000;
      benefits.add('Standard B2B pricing (15% off retail)');
    } else if (ytdSpend < 25000) {
      tier = 'Silver';
      nextTier = 'Gold';
      nextLimit = 25000;
      benefits.add('5% volume discount on quotes');
      benefits.add('Priority customer support');
      benefits.add('Early access to new products');
    } else if (ytdSpend < 50000) {
      tier = 'Gold';
      nextTier = 'Platinum';
      nextLimit = 50000;
      benefits.add('10% volume discount on quotes');
      benefits.add('Dedicated account manager');
      benefits.add('Free shipping on all orders');
      benefits.add('Quarterly business reviews');
    } else {
      tier = 'Platinum';
      nextTier = null;
      nextLimit = null;
      benefits.add('15% volume discount on quotes');
      benefits.add('Custom contract terms negotiation');
      benefits.add('White-glove dedicated service');
      benefits.add('VIP events and product launches access');
      benefits.add('Priority access to limited inventory');
    }

    String summary = '🏆 Your TalFlow B2B Tier: **' + tier + '**\n\n';
    summary += '💰 YTD Spend: $' + ytdSpend.setScale(0).format() + '\n\n';
    summary += 'Your benefits:\n';
    for (String b : benefits) {
      summary += '✓ ' + b + '\n';
    }

    if (nextTier != null && nextLimit != null) {
      Decimal toGo = nextLimit - ytdSpend;
      summary +=
        '\n⬆️ Progress to ' +
        nextTier +
        ': $' +
        toGo.setScale(0).format() +
        ' more to reach the next level.';
    } else {
      summary += '\n🌟 You\'re at the highest tier! Enjoy all premium benefits.';
    }

    Output out = new Output();
    out.tierInfo = summary;
    out.currentTier = tier;
    out.ytdSpend = ytdSpend;
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
