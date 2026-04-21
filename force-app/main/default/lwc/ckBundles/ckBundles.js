import { LightningElement, track, wire } from 'lwc';
import getBundles from '@salesforce/apex/CkProductController.getBundles';

export default class CkBundles extends LightningElement {
    @track bundles = [];
    @track isLoading = true;

    @wire(getBundles, { maxBundles: 4 })
    wiredBundles({ data, error }) {
        if (data) {
            this.bundles = data;
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
        }
    }

    get hasBundles() { return this.bundles.length > 0; }

    handleAddBundle(event) {
        event.preventDefault();
        const bundleId = event.currentTarget.dataset.id;
        const bundle = this.bundles.find(b => b.id === bundleId);
        if (bundle) {
            bundle.items.forEach(item => {
                window.dispatchEvent(new CustomEvent('addtocart', {
                    detail: {
                        productId: item.productId,
                        name: item.name,
                        image: item.image,
                        unitPrice: item.priceNum
                    }
                }));
            });
        }
    }
}