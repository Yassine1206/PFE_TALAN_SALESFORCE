import { LightningElement, track, wire } from 'lwc';
import getCategoryCards from '@salesforce/apex/CkProductController.getCategoryCards';
import basePath from '@salesforce/community/basePath';

export default class CkShopByCategory extends LightningElement {
    @track categories = [];
    @track isLoading = true;

    // Dans le wire handler :
    @wire(getCategoryCards)
    wiredCats({ data, error }) {
        if (data) {
            this.categories = data.map(cat => ({
                ...cat,
                url: basePath + '/category?cat=' + encodeURIComponent(cat.name)
            }));
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
        }
    }

    get hasCategories() { return this.categories.length > 0; }
}