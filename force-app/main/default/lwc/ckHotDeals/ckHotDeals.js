import { LightningElement, track, wire } from 'lwc';
import getPromoProducts from '@salesforce/apex/CkProductController.getPromoProducts';
import getHotDealsEndDate from '@salesforce/apex/CkProductController.getHotDealsEndDate';

export default class CkHotDeals extends LightningElement {
    @track products  = [];
    @track isLoading = true;
    @track countdown = { days: '00', hours: '00', minutes: '00', seconds: '00' };
    @track isExpired = false;
    _timer;
    _endTime;

    @wire(getPromoProducts, { maxProducts: 6 })
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => ({
                ...p,
                // FIX : priceNum vient d'Apex en Decimal → Number() direct
                priceNum       : p.priceNum != null ? Number(p.priceNum) : 0,
                // FIX : oldPrice est une string '$XX.XX' → extraire le nombre
                oldPriceNum    : p.oldPrice
                    ? Number(String(p.oldPrice).replace('$', '').trim()) || null
                    : null,
                isOnSale       : true,
                discountPercent: p.discountPercent || 0,
                detailUrl      : '/s/product-detail?productId=' + p.id,
                badgeText      : '-' + (p.discountPercent || 0) + '%'
            }));
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.loadEndDate();
    }

    disconnectedCallback() {
        clearInterval(this._timer);
    }

    loadEndDate() {
        getHotDealsEndDate()
            .then(result => {
                if (result) {
                    this._endTime = new Date(result).getTime();
                } else {
                    const end = new Date();
                    end.setDate(end.getDate() + 7);
                    this._endTime = end.getTime();
                }
                this.startCountdown();
            })
            .catch(() => {
                const end = new Date();
                end.setDate(end.getDate() + 7);
                this._endTime = end.getTime();
                this.startCountdown();
            });
    }

    startCountdown() {
        this.updateCountdown();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setInterval(() => this.updateCountdown(), 1000);
    }

    updateCountdown() {
        const diff = this._endTime - Date.now();
        if (diff <= 0) {
            this.countdown = { days: '00', hours: '00', minutes: '00', seconds: '00' };
            this.isExpired = true;
            clearInterval(this._timer);
            return;
        }
        const d = Math.floor(diff / 86400000);
        const h = Math.floor((diff % 86400000) / 3600000);
        const m = Math.floor((diff % 3600000) / 60000);
        const s = Math.floor((diff % 60000) / 1000);
        this.countdown = {
            days   : String(d).padStart(2, '0'),
            hours  : String(h).padStart(2, '0'),
            minutes: String(m).padStart(2, '0'),
            seconds: String(s).padStart(2, '0')
        };
    }

    get hasProducts() {
        return this.products.length > 0 && !this.isExpired;
    }

    // handleQuickAdd supprimé — ckProductCard dispatche directement sur window
}