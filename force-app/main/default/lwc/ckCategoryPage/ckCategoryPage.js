import { LightningElement, track } from 'lwc';
import getCategoryProducts from '@salesforce/apex/CkProductController.getCategoryProducts';
import getCategories from '@salesforce/apex/CkProductController.getCategories';
import basePath from '@salesforce/community/basePath';


export default class CkCategoryPage extends LightningElement {
    @track products = [];
    @track allCategories = [];
    @track subcategories = [];
    @track isLoading = true;
    @track totalCount = 0;

    // Filters
    @track category = '';
    @track subcategory = '';
    @track sortBy = 'rating';
    @track minPrice = null;
    @track maxPrice = null;
    @track onSaleOnly = false;
    @track availability = '';
    @track pageNumber = 1;
    pageSize = 9;

    // Filter panel visibility (mobile)
    @track showFilters = false;

    connectedCallback() {
        const url = new URL(window.location.href);
        this.category = url.searchParams.get('cat') || '';
        this.subcategory = url.searchParams.get('sub') || '';
        this.loadCategories();
        this.loadProducts();
    }

    loadCategories() {
        getCategories()
            .then(data => {
                this.allCategories = data.filter(c => c !== 'All');
            })
            .catch(() => { });
    }

    loadProducts() {
        this.isLoading = true;
        getCategoryProducts({
            category: this.category,
            subcategory: this.subcategory,
            sortBy: this.sortBy,
            minPrice: this.minPrice,
            maxPrice: this.maxPrice,
            onSaleOnly: this.onSaleOnly,
            availability: this.availability,
            pageNumber: this.pageNumber,
            pageSize: this.pageSize
        })
            .then(result => {
                this.products = result.products.map(p => ({
                    ...p,
                    // priceNum vient directement d'Apex en Decimal → Number() safe
                    priceNum: p.priceNum != null ? Number(p.priceNum) : 0,
                    // oldPrice est une string '$XX.XX' → extraire le nombre
                    oldPriceNum: p.oldPrice
                        ? Number(String(p.oldPrice).replace('$', '').trim()) || null
                        : null,
                    detailUrl: basePath + '/product-detail?productId=' + p.id
                }));
                this.totalCount = result.totalCount;
                this.subcategories = result.subcategories || [];
                this.isLoading = false;
            })
            .catch(() => {
                this.products = [];
                this.totalCount = 0;
                this.isLoading = false;
            });
    }

    // Supprimer handleQuickAdd — plus nécessaire
    // ckProductCard dispatche directement sur window

    // handleQuickAdd(event) {
    //     // ckProductCard envoie unitPrice (pas price)
    //     const { productId, name, image, unitPrice } = event.detail;
    //     window.dispatchEvent(new CustomEvent('addtocart', {
    //         detail: {
    //             productId: productId,
    //             name: name || '',
    //             image: image || '',
    //             unitPrice: unitPrice != null ? Number(unitPrice) : 0
    //         }
    //     }));
    // }

    // ═══ Getters ═══
    get hasProducts() { return this.products.length > 0; }
    get pageTitle() {
        if (this.subcategory) return this.subcategory;
        if (this.category) return this.category;
        return 'All Products';
    }
    get resultText() { return this.totalCount + ' product' + (this.totalCount !== 1 ? 's' : ''); }
    get totalPages() { return Math.ceil(this.totalCount / this.pageSize); }
    get hasPrevious() { return this.pageNumber > 1; }
    get hasNext() { return this.pageNumber < this.totalPages; }
    get pageInfo() { return 'Page ' + this.pageNumber + ' / ' + this.totalPages; }
    get hasSubcategories() { return this.subcategories.length > 0; }
    get filterBtnClass() { return this.showFilters ? 'cp-filter-toggle cp-filter-toggle-active' : 'cp-filter-toggle'; }

    get sortOptions() {
        return [
            { label: 'Meilleure note', value: 'rating', selected: this.sortBy === 'rating' },
            { label: 'Prix croissant', value: 'price_asc', selected: this.sortBy === 'price_asc' },
            { label: 'Prix decroissant', value: 'price_desc', selected: this.sortBy === 'price_desc' },
            { label: 'A → Z', value: 'name_asc', selected: this.sortBy === 'name_asc' },
            { label: 'Z → A', value: 'name_desc', selected: this.sortBy === 'name_desc' }
        ];
    }

    get availabilityOptions() {
        return [
            { label: 'Tous', value: '', selected: this.availability === '' },
            { label: 'En stock', value: 'En stock', selected: this.availability === 'En stock' },
            { label: 'En arrivage', value: 'En arrivage', selected: this.availability === 'En arrivage' },
            { label: 'Sur commande 48h', value: 'Sur commande 48h', selected: this.availability === 'Sur commande 48h' },
            { label: 'Epuise', value: 'Epuise', selected: this.availability === 'Epuise' }
        ];
    }

    get categoryButtons() {
        return this.allCategories.map(cat => ({
            name: cat,
            className: cat === this.category ? 'cp-cat-btn cp-cat-btn-active' : 'cp-cat-btn'
        }));
    }

    get subButtons() {
        return this.subcategories.map(sub => ({
            name: sub,
            className: sub === this.subcategory ? 'cp-sub-btn cp-sub-btn-active' : 'cp-sub-btn'
        }));
    }
    get saleButtonClass() {
        return this.onSaleOnly ? 'cp-sale-btn cp-sale-btn-active' : 'cp-sale-btn';
    }

    // ═══ Handlers ═══
    handleCategoryClick(event) {
        const cat = event.currentTarget.dataset.cat;
        if (this.category === cat) {
            this.category = '';
        } else {
            this.category = cat;
        }
        this.subcategory = '';
        this.pageNumber = 1;
        this.updateUrl();
        this.loadProducts();
    }

    handleSubClick(event) {
        const sub = event.currentTarget.dataset.sub;
        if (this.subcategory === sub) {
            this.subcategory = '';
        } else {
            this.subcategory = sub;
        }
        this.pageNumber = 1;
        this.updateUrl();
        this.loadProducts();
    }

    handleSortChange(event) {
        this.sortBy = event.target.value;
        this.pageNumber = 1;
        this.loadProducts();
    }

    handleMinPrice(event) {
        this.minPrice = event.target.value ? parseFloat(event.target.value) : null;
    }

    handleMaxPrice(event) {
        this.maxPrice = event.target.value ? parseFloat(event.target.value) : null;
    }

    handlePriceApply() {
        this.pageNumber = 1;
        this.loadProducts();
    }

    handleSaleToggle() {
        this.onSaleOnly = !this.onSaleOnly;
        this.pageNumber = 1;
        this.loadProducts();
    }

    handleAvailabilityChange(event) {
        this.availability = event.target.value;
        this.pageNumber = 1;
        this.loadProducts();
    }

    handleClearFilters() {
        this.subcategory = '';
        this.sortBy = 'rating';
        this.minPrice = null;
        this.maxPrice = null;
        this.onSaleOnly = false;
        this.availability = '';
        this.pageNumber = 1;
        this.updateUrl();
        this.loadProducts();
    }

    handleToggleFilters() {
        this.showFilters = !this.showFilters;
    }

    handlePrevious() {
        if (this.hasPrevious) {
            this.pageNumber--;
            this.loadProducts();
            this.scrollToTop();
        }
    }

    handleNext() {
        if (this.hasNext) {
            this.pageNumber++;
            this.loadProducts();
            this.scrollToTop();
        }
    }

    scrollToTop() {
        const el = this.template.querySelector('.cp-wrapper');
        if (el) el.scrollIntoView({ behavior: 'smooth' });
    }

    updateUrl() {
        let url = basePath + '/category';
        const params = [];
        if (this.category) params.push('cat=' + encodeURIComponent(this.category));
        if (this.subcategory) params.push('sub=' + encodeURIComponent(this.subcategory));
        if (params.length) url += '?' + params.join('&');
        window.history.replaceState(null, '', url);
    }


}