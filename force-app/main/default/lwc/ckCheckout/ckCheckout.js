import { LightningElement, track } from 'lwc';
import getCheckoutData from '@salesforce/apex/CkCheckoutController.getCheckoutData';
import recalculateTaxes from '@salesforce/apex/CkCheckoutController.recalculateTaxes';
import validatePromoCode from '@salesforce/apex/CkCheckoutController.validatePromoCode';
import processCheckout from '@salesforce/apex/CkCheckoutController.processCheckout';

const COUNTRIES = [
    { label: 'Tunisia', value: 'TN' },
    { label: 'France', value: 'FR' },
    { label: 'Germany', value: 'DE' },
    { label: 'Italy', value: 'IT' },
    { label: 'Spain', value: 'ES' },
    { label: 'United Kingdom', value: 'GB' },
    { label: 'United States', value: 'US' },
    { label: 'Canada', value: 'CA' },
    { label: 'Australia', value: 'AU' },
    { label: 'Morocco', value: 'MA' },
    { label: 'Algeria', value: 'DZ' },
    { label: 'Saudi Arabia', value: 'SA' },
    { label: 'UAE', value: 'AE' },
    { label: 'Turkey', value: 'TR' },
    { label: 'Egypt', value: 'EG' }
];

export default class CkCheckout extends LightningElement {

    @track currentStep = 1;
    @track isLoading = false;
    @track isTaxLoading = false;
    @track errorMessage = '';
    @track promoMessage = '';
    @track promoValid = false;
    @track cartItems = [];

    @track form = {
        fullName: '',
        email: '',
        street: '',
        city: '',
        postalCode: '',
        countryCode: 'TN',
        phone: '',
        promoCode: '',
        paymentMethod: 'Card'
    };

    @track summary = {
        subtotal: 0,
        discount: 0,
        taxRate: 0,
        taxAmount: 0,
        shippingCost: 0,
        totalTTC: 0,
        deliveryDays: '',
        isFallbackRate: false
    };

    connectedCallback() {
        this.loadCheckoutData();
    }

    loadCheckoutData() {
        this.isLoading = true;
        getCheckoutData()
            .then(data => {
                if (data.isGuest) {
                    window.location.href = '/s/login';
                    return;
                }
                this.form = {
                    ...this.form,
                    fullName: data.fullName || '',
                    email: data.email || '',
                    street: data.street || '',
                    city: data.city || '',
                    postalCode: data.postalCode || '',
                    countryCode: data.country || 'TN',
                    phone: data.phone || ''
                };
                this.cartItems = (data.items || []).map(i => ({
                    id: i.itemId,
                    name: i.name,
                    image: i.image,
                    quantity: i.quantity,
                    price: '$' + (i.unitPrice || 0).toFixed(2)
                }));
                if (data.summary) {
                    this.summary = { ...data.summary };
                }
                this.isLoading = false;
            })
            .catch(() => {
                this.isLoading = false;
                this.errorMessage = 'Failed to load checkout data.';
            });
    }

    // ── Inputs ───────────────────────────────────────────────
    handleInput(event) {
        const field = event.currentTarget.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        this.errorMessage = '';
    }

    handleCountryChange(event) {
        this.form = { ...this.form, countryCode: event.target.value };
        this.refreshTaxes();
    }

    refreshTaxes(discountOverride) {
        this.isTaxLoading = true;
        const discount = discountOverride !== undefined
            ? discountOverride
            : (this.summary.discount || 0);

        recalculateTaxes({
            subtotal: this.summary.subtotal,
            countryCode: this.form.countryCode,
            discountAmount: discount
        })
            .then(s => {
                this.summary = { ...s };
                this.isTaxLoading = false;
            })
            .catch(() => {
                this.isTaxLoading = false;
            });
    }

    // ── Promo ────────────────────────────────────────────────
    applyPromo() {
        if (!this.form.promoCode) return;
        validatePromoCode({
            code: this.form.promoCode,
            subtotal: this.summary.subtotal
        })
            .then(result => {
                this.promoValid = result.valid;
                this.promoMessage = result.message;
                if (result.valid) {
                    this.refreshTaxes(result.discountAmount);
                }
            })
            .catch(() => {
                this.promoMessage = 'Error validating promo code.';
            });
    }

    // ── Navigation ───────────────────────────────────────────
    goStep1() {
        this.currentStep = 1;
        this.errorMessage = '';
    }

    goStep2() {
        if (!this.validateStep1()) return;
        this.currentStep = 2;
        this.refreshTaxes();
    }

    goStep3() {
        this.currentStep = 3;
        this.errorMessage = '';
    }

    goStep4() {
        this.currentStep = 4;
        this.errorMessage = '';
    }

    // ── Payment ──────────────────────────────────────────────
    selectCard() {
        this.form = { ...this.form, paymentMethod: 'Card' };
        console.log('paymentMethod set to:', this.form.paymentMethod);
    }

    selectCOD() {
        this.form = { ...this.form, paymentMethod: 'COD' };
        console.log('paymentMethod set to:', this.form.paymentMethod);
    }

    // ── Place Order ──────────────────────────────────────────
    placeOrder() {
        this.isLoading = true;
        this.errorMessage = '';
        console.log('form complet:', JSON.stringify({
            street: this.form.street,
            city: this.form.city,
            postalCode: this.form.postalCode,
            countryCode: this.form.countryCode,
            phone: this.form.phone,
            email: this.form.email
        }));
        processCheckout({
            req: {
                street: this.form.street || '',
                city: this.form.city || '',
                postalCode: this.form.postalCode || '',
                countryCode: this.form.countryCode || 'TN',
                email: this.form.email || '',
                phone: this.form.phone || '',
                paymentMethod: this.form.paymentMethod || 'Card',
                discountAmount: this.summary.discount || 0,
                promoCode: this.form.promoCode || ''
            }
        })
            .then(result => {
                this.isLoading = false;
                console.log('result:', JSON.stringify(result));
                

                if (result.success) {
                    if (this.form.paymentMethod === 'COD') {
                        window.location.href = result.redirectUrl;
                    } else {
                        const redirectUrl = result.redirectUrl || '';
                        const idx = redirectUrl.indexOf(':::');

                        if (idx > -1) {
                            const stripeUrl = redirectUrl.substring(0, idx);
                            const orderId = redirectUrl.substring(idx + 3);

                            // FIX : stocker orderId avant redirect Stripe
                            // car Stripe ne remet pas orderId dans l'URL de retour
                            sessionStorage.setItem('pendingOrderId', orderId);

                            if (stripeUrl && stripeUrl.startsWith('https://')) {
                                window.location.href = stripeUrl;
                            } else {
                                this.errorMessage = 'URL de paiement invalide: ' + stripeUrl;
                            }
                        } else {
                            // Pas de séparateur → URL entière
                            if (redirectUrl.startsWith('https://')) {
                                window.location.href = redirectUrl;
                            } else {
                                this.errorMessage = 'URL de paiement invalide: ' + redirectUrl;
                            }
                        }
                    }
                } else {
                    this.errorMessage = result.errorMessage || 'An error occurred.';
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = (error.body && error.body.message)
                    ? error.body.message
                    : 'An error occurred. Please try again.';
            });
    }

    // ── Validation ───────────────────────────────────────────
    validateStep1() {
        const f = this.form;
        if (!f.fullName || !f.email || !f.street || !f.city || !f.countryCode) {
            this.errorMessage = 'Please fill all required fields.';
            return false;
        }
        if (!f.email.includes('@')) {
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }
        this.errorMessage = '';
        return true;
    }

    // ── Getters ──────────────────────────────────────────────
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }

    get isCardSelected() { return this.form.paymentMethod === 'Card'; }
    get isCODSelected() { return this.form.paymentMethod === 'COD'; }

    get hasDiscount() {
        return this.summary.discount && this.summary.discount > 0;
    }

    get countries() {
        return COUNTRIES.map(c => ({
            ...c,
            selected: c.value === this.form.countryCode
        }));
    }

    get steps() {
        const labels = ['Address', 'Shipping', 'Payment', 'Review'];
        return labels.map((label, i) => ({
            id: i + 1,
            num: i + 1,
            label,
            cls: 'ck-step'
                + (this.currentStep === i + 1 ? ' ck-step-active' : '')
                + (this.currentStep > i + 1 ? ' ck-step-completed' : '')
        }));
    }

    get cardMethodCls() {
        return 'ck-method' + (this.isCardSelected ? ' ck-method-selected' : '');
    }

    get codMethodCls() {
        return 'ck-method' + (this.isCODSelected ? ' ck-method-selected' : '');
    }

    get paymentMethodBadge() {
        return this.isCODSelected
            ? 'ck-payment-badge ck-badge-green'
            : 'ck-payment-badge';
    }

    get promoMessageCls() {
        return this.promoValid ? 'ck-promo-success' : 'ck-promo-error';
    }
}