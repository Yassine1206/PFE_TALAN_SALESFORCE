import { LightningElement, track } from 'lwc';
import getUserFavorites from '@salesforce/apex/CkFavoriteController.getUserFavorites';
import toggleFavorite from '@salesforce/apex/CkFavoriteController.toggleFavorite';

export default class CkFavorites extends LightningElement {
    @track favorites = [];
    @track isLoading = true;
    @track removingId = null;

    connectedCallback() {
        this.loadFavorites();
    }

    loadFavorites() {
        this.isLoading = true;
        getUserFavorites()
            .then(result => {
                this.favorites = result.map((f, index) => ({
                    ...f,
                    detailUrl: '/s/product-detail?productId=' + f.productId,
                    isFirst: index === 0,
                    isRemoving: false,
                    // priceNum vient d'Apex en Decimal → Number() direct
                    priceNum: f.priceNum != null ? Number(f.priceNum) : 0,
                    // price est déjà formatée '$XX.XX' depuis Apex
                    price: f.price || '$0.00'
                }));
                this.isLoading = false;
            })
            .catch(() => {
                this.favorites = [];
                this.isLoading = false;
            });
    }

    handleRemove(event) {
        event.preventDefault();
        event.stopPropagation();
        const productId = event.currentTarget.dataset.id;
        this.removingId = productId;

        toggleFavorite({ productId })
            .then(() => {
                this.favorites = this.favorites.filter(f => f.productId !== productId);
                if (this.favorites.length > 0) {
                    this.favorites[0] = { ...this.favorites[0], isFirst: true };
                    for (let i = 1; i < this.favorites.length; i++) {
                        this.favorites[i] = { ...this.favorites[i], isFirst: false };
                    }
                }
                this.removingId = null;
            })
            .catch(() => {
                this.removingId = null;
            });
    }

    handleQuickAdd(event) {
        event.preventDefault();
        event.stopPropagation();

        const productId = event.currentTarget.dataset.id;
        const item = this.favorites.find(f => f.productId === productId);
        if (!item) return;

        window.dispatchEvent(new CustomEvent('addtocart', {
            detail: {
                productId: item.productId,
                name: item.name || '',
                image: item.image || '',
                unitPrice: item.priceNum || 0
            }
        }));
    }

    handleAddAll() {
        this.favorites.forEach(f => {
            window.dispatchEvent(new CustomEvent('addtocart', {
                detail: {
                    productId: f.productId,
                    name: f.name || '',
                    image: f.image || '',
                    unitPrice: f.priceNum || 0
                }
            }));
        });
    }

    get hasFavorites() { return this.favorites.length > 0; }
    get favoriteCount() { return this.favorites.length; }
    get favoriteCountText() {
        return this.favorites.length + ' item' + (this.favorites.length !== 1 ? 's' : '') + ' saved';
    }
    get heroProduct() { return this.favorites.length > 0 ? this.favorites[0] : null; }
    get gridProducts() { return this.favorites.length > 1 ? this.favorites.slice(1) : []; }
    get hasGridProducts() { return this.gridProducts.length > 0; }
}