import { LightningElement, track } from 'lwc';
import confirmOrder from '@salesforce/apex/CkCheckoutController.confirmOrder';

export default class CkOrderConfirmation extends LightningElement {
    @track isLoading = true;
    @track isSuccess = false;
    @track errorMessage = '';
    @track orderNumber = '';
    @track totalTTC = '';
    @track paymentMethod = '';
    @track shippingTo = '';
    @track orderDate = '';

    connectedCallback() {
        this.verifyPayment();
    }

    verifyPayment() {
        const url = new URL(window.location.href);
        const sessionId = url.searchParams.get('session_id');

        let orderId = url.searchParams.get('orderId');
        if (!orderId) {
            orderId = sessionStorage.getItem('pendingOrderId');
        }
        sessionStorage.removeItem('pendingOrderId');

        if (!sessionId) {
            this.isLoading = false;
            this.errorMessage = 'Invalid payment session.';
            return;
        }

        confirmOrder({ orderId: orderId, sessionId: sessionId })
            .then(result => {
                this.isLoading = false;
                this.isSuccess = result.success;

                if (result.success) {
                    this.orderNumber = result.orderNumber || '';
                    this.totalTTC = result.totalTTC
                        ? Number(result.totalTTC).toFixed(2) : '0.00';
                    this.paymentMethod = result.paymentMethod || '';
                    this.shippingTo = (result.shippingCity || '')
                        + (result.shippingCity && result.shippingCountry ? ', ' : '')
                        + (result.shippingCountry || '');
                    this.orderDate = result.orderDate || '';
                } else {
                    this.errorMessage = 'Payment verification failed. Please contact support.';
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = error.body ? error.body.message : 'Verification failed.';
            });
    }
}