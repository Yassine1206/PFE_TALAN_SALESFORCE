import { LightningElement, track } from 'lwc';
import searchProducts from '@salesforce/apex/CkProductController.searchProducts';

export default class CkSearch extends LightningElement {
    @track searchTerm = '';
    @track results = [];
    @track showDropdown = false;
    @track isSearching = false;

    _debounceTimer;

    handleInput(event) {
        this.searchTerm = event.target.value;

        clearTimeout(this._debounceTimer);

        if (this.searchTerm.length < 2) {
            this.results = [];
            this.showDropdown = false;
            return;
        }

        this.isSearching = true;
        this.showDropdown = true;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.doSearch();
        }, 300);
    }

    doSearch() {
        searchProducts({ searchTerm: this.searchTerm })
            .then(result => {
                this.results = result.map(p => ({
                    ...p,
                    detailUrl: '/s/product-detail?productId=' + p.id
                }));
                this.isSearching = false;
            })
            .catch(() => {
                this.results = [];
                this.isSearching = false;
            });
    }

    handleFocus() {
        if (this.searchTerm.length >= 2 && this.results.length > 0) {
            this.showDropdown = true;
        }
    }

    handleBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showDropdown = false;
        }, 200);
    }

    handleResultClick(event) {
        const productId = event.currentTarget.dataset.id;
        window.location.href = '/s/product-detail?productId=' + productId;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && this.searchTerm.length >= 2) {
            this.showDropdown = false;
            window.location.href = '/s/search-results?q=' + encodeURIComponent(this.searchTerm);
        }
    }

    handleViewAll() {
        window.location.href = '/s/search-results?q=' + encodeURIComponent(this.searchTerm);
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get noResults() {
        return !this.isSearching && this.searchTerm.length >= 2 && this.results.length === 0;
    }

    get dropdownClass() {
        return this.showDropdown ? 'search-dropdown search-dropdown-visible' : 'search-dropdown';
    }
}