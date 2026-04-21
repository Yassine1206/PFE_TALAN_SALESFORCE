import { LightningElement, track, wire } from 'lwc';
import searchProductsFull from '@salesforce/apex/CkProductController.searchProductsFull';
import getCategories from '@salesforce/apex/CkProductController.getCategories';

export default class CkSearchResults extends LightningElement {
    @track searchTerm       = '';
    @track selectedCategory = 'All';
    @track sortBy           = 'rating';
    @track minPrice         = null;
    @track maxPrice         = null;
    @track pageNumber       = 1;
    @track pageSize         = 12;
    @track results          = [];
    @track totalCount       = 0;
    @track categories       = [];
    @track isLoading        = true;

    @wire(getCategories)
    wiredCategories({ data }) {
        if (data) {
            this.categories = data.map(cat => ({
                name     : cat,
                className: cat === this.selectedCategory
                    ? 'filter-btn filter-btn-active'
                    : 'filter-btn'
            }));
        }
    }

    connectedCallback() {
        const url = new URL(window.location.href);
        this.searchTerm = url.searchParams.get('q') || '';
        this.loadResults();
    }

    loadResults() {
        this.isLoading = true;
        searchProductsFull({
            searchTerm : this.searchTerm,
            category   : this.selectedCategory,
            sortBy     : this.sortBy,
            minPrice   : this.minPrice,
            maxPrice   : this.maxPrice,
            pageNumber : this.pageNumber,
            pageSize   : this.pageSize
        })
        .then(result => {
            this.results = result.products.map(p => ({
                ...p,
                // FIX : priceNum vient d'Apex en Decimal → Number() direct
                priceNum : p.priceNum != null ? Number(p.priceNum) : 0,
                detailUrl: '/s/product-detail?productId=' + p.id
            }));
            this.totalCount = result.totalCount;
            this.isLoading  = false;
        })
        .catch(() => {
            this.results    = [];
            this.totalCount = 0;
            this.isLoading  = false;
        });
    }

    get hasResults()     { return this.results.length > 0; }
    get resultCountText(){ return this.totalCount + ' product' + (this.totalCount !== 1 ? 's' : '') + ' found'; }
    get totalPages()     { return Math.ceil(this.totalCount / this.pageSize); }
    get hasPrevious()    { return this.pageNumber > 1; }
    get hasNext()        { return this.pageNumber < this.totalPages; }
    get pageInfo()       { return 'Page ' + this.pageNumber + ' of ' + this.totalPages; }

    // FIX : disabled={hasPrevious} était inversé dans le HTML original
    get isFirstPage()    { return this.pageNumber <= 1; }
    get isLastPage()     { return this.pageNumber >= this.totalPages; }

    get sortOptions() {
        return [
            { label: 'Best Rating',       value: 'rating',     selected: this.sortBy === 'rating'     },
            { label: 'Price: Low to High',value: 'price_asc',  selected: this.sortBy === 'price_asc'  },
            { label: 'Price: High to Low',value: 'price_desc', selected: this.sortBy === 'price_desc' },
            { label: 'Name: A to Z',      value: 'name_asc',   selected: this.sortBy === 'name_asc'   }
        ];
    }

    handleSearchInput(event)   { this.searchTerm = event.target.value; }

    handleSearchKeyDown(event) {
        if (event.key === 'Enter') {
            this.pageNumber = 1;
            this.loadResults();
        }
    }

    handleSearchClick() {
        this.pageNumber = 1;
        this.loadResults();
    }

    handleCategoryClick(event) {
        this.selectedCategory = event.currentTarget.dataset.cat;
        this.categories = this.categories.map(cat => ({
            ...cat,
            className: cat.name === this.selectedCategory
                ? 'filter-btn filter-btn-active'
                : 'filter-btn'
        }));
        this.pageNumber = 1;
        this.loadResults();
    }

    handleSortChange(event) {
        this.sortBy     = event.target.value;
        this.pageNumber = 1;
        this.loadResults();
    }

    handleMinPrice(event) {
        this.minPrice = event.target.value ? parseFloat(event.target.value) : null;
    }

    handleMaxPrice(event) {
        this.maxPrice = event.target.value ? parseFloat(event.target.value) : null;
    }

    handlePriceFilter() {
        this.pageNumber = 1;
        this.loadResults();
    }

    handleClearFilters() {
        this.selectedCategory = 'All';
        this.sortBy           = 'rating';
        this.minPrice         = null;
        this.maxPrice         = null;
        this.pageNumber       = 1;
        this.categories = this.categories.map(cat => ({
            ...cat,
            className: cat.name === 'All'
                ? 'filter-btn filter-btn-active'
                : 'filter-btn'
        }));
        this.loadResults();
    }

    handlePrevious() {
        if (this.hasPrevious) {
            this.pageNumber--;
            this.loadResults();
            this.scrollToTop();
        }
    }

    handleNext() {
        if (this.hasNext) {
            this.pageNumber++;
            this.loadResults();
            this.scrollToTop();
        }
    }

    scrollToTop() {
        const el = this.template.querySelector('.sr-wrapper');
        if (el) el.scrollIntoView({ behavior: 'smooth' });
    }

    // handleQuickAdd supprimé — ckProductCard dispatche directement sur window
}