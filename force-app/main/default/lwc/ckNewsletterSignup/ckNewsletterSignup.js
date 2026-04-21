import { LightningElement, api, track } from 'lwc';
export default class CkNewsletterSignup extends LightningElement {
    @api title = 'Join the cloud.';
    @api description = 'Join the CloudKicks community for exclusive drops, discounts, and early access.';
    @track email = '';
    handleEmailChange(e) { this.email = e.target.value; }
    handleSubmit() {
        if (this.email) {
            this.dispatchEvent(new CustomEvent('subscribe', { detail: { email: this.email } }));
            this.email = '';
        }
    }
}
