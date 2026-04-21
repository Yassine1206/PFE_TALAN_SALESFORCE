import { LightningElement, api, track, wire } from 'lwc';
import getProducts from '@salesforce/apex/CkProductController.getProducts';
import getCategories from '@salesforce/apex/CkProductController.getCategories';

export default class CkProductCarousel extends LightningElement {
    @api sectionTitle = 'Signature Series';
    @api sectionSubtitle = 'Experience our most coveted drops.';
    @api maxProducts = 10;
    @api visibleCount = 4;

    @track carouselItems = [];
    @track categories = [];
    @track selectedCategory = 'All';
    @track isLoading = true;
    @track currentIndex = 0;

    autoPlayInterval;
    isHovered = false;
    _listenersAdded = false;

    get maxProductsInt() {
        return parseInt(this.maxProducts, 10) || 10;
    }

    @wire(getCategories)
    wiredCategories({ data, error }) {
        if (data) {
            this.categories = data.map(cat => ({
                name: cat,
                className: cat === this.selectedCategory ? 'cat-btn cat-btn-active' : 'cat-btn'
            }));
        }
        if (error) {
            console.error('Categories error:', error);
        }
    }

    @wire(getProducts, { maxProducts: '$maxProductsInt', category: '$selectedCategory' })
    wiredProducts({ data, error }) {
        if (data) {
            this.carouselItems = data.map(p => ({
                id: p.id,
                name: p.name,
                price: p.price,
                priceNum: p.priceNum || (p.price ? parseFloat(p.price.replace('$', '')) : 0),
                image: p.image,
                description: p.description,
                category: p.category,
                rating: p.rating
            }));
            this.isLoading = false;
        }
        if (error) {
            console.error('Products error:', error);
            this.isLoading = false;
        }
    }

    get hasProducts() {
        return this.carouselItems.length > 0;
    }

    connectedCallback() {
        this.startAutoPlay();
    }

    disconnectedCallback() {
        this.stopAutoPlay();
    }

    renderedCallback() {
        if (!this._listenersAdded) {
            const track = this.template.querySelector('[data-id="track"]');
            if (track) {
                track.addEventListener('mouseenter', () => {
                    this.isHovered = true;
                    this.stopAutoPlay();
                });
                track.addEventListener('mouseleave', () => {
                    this.isHovered = false;
                    this.startAutoPlay();
                });
                this._listenersAdded = true;
            }
        }
    }

    handleCategoryClick(event) {
        this.selectedCategory = event.currentTarget.dataset.cat;
        this.isLoading = true;
        this.categories = this.categories.map(cat => ({
            ...cat,
            className: cat.name === this.selectedCategory ? 'cat-btn cat-btn-active' : 'cat-btn'
        }));
        // Reset scroll
        const track = this.template.querySelector('[data-id="track"]');
        if (track) {
            track.scrollTo({ left: 0, behavior: 'smooth' });
        }
        this.currentIndex = 0;
    }

    startAutoPlay() {
        this.stopAutoPlay();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.autoPlayInterval = setInterval(() => {
            if (!this.isHovered) {
                this.scrollRight();
            }
        }, 3000);
    }

    stopAutoPlay() {
        if (this.autoPlayInterval) {
            clearInterval(this.autoPlayInterval);
        }
    }

    scrollLeft() {
        const track = this.template.querySelector('[data-id="track"]');
        if (track) {
            const card = track.querySelector('.ck-card');
            if (!card) return;
            const cardWidth = card.offsetWidth + 24;

            if (track.scrollLeft <= 0) {
                track.scrollTo({ left: track.scrollWidth, behavior: 'smooth' });
                this.currentIndex = this.carouselItems.length - 1;
            } else {
                track.scrollBy({ left: -cardWidth, behavior: 'smooth' });
                this.currentIndex = Math.max(0, this.currentIndex - 1);
            }
        }
    }

    scrollRight() {
        const track = this.template.querySelector('[data-id="track"]');
        if (track) {
            const card = track.querySelector('.ck-card');
            if (!card) return;
            const cardWidth = card.offsetWidth + 24;
            const maxScroll = track.scrollWidth - track.clientWidth;

            if (track.scrollLeft >= maxScroll - 5) {
                track.scrollTo({ left: 0, behavior: 'smooth' });
                this.currentIndex = 0;
            } else {
                track.scrollBy({ left: cardWidth, behavior: 'smooth' });
                this.currentIndex = this.currentIndex + 1;
            }
        }
    }

    handleQuickAdd(event) {
        const { productId, name, image, price } = event.detail;
        window.dispatchEvent(new CustomEvent('addtocart', {
            detail: {
                productId: productId,
                name: name,
                image: image,
                unitPrice: price
            }
        }));
    }

    handleViewDetails(event) {
        const productId = event.currentTarget.dataset.id;
        window.location.href = '/s/product-detail?productId=' + productId;
    }
}