import { LightningElement, track } from 'lwc';
import getProductById from '@salesforce/apex/CkProductController.getProductById';
import getRelatedProducts from '@salesforce/apex/CkProductController.getRelatedProducts';
import toggleFavorite from '@salesforce/apex/CkFavoriteController.toggleFavorite';
import isFavoriteApex from '@salesforce/apex/CkFavoriteController.isFavorite';
import trackProductView from '@salesforce/apex/CkFavoriteController.trackProductView';
import checkStock from '@salesforce/apex/CkStockService.checkStock';

export default class CkProductDetail extends LightningElement {
    @track product = null;
    @track relatedProducts = [];
    @track isLoading = true;
    @track quantity = 1;
    @track isFavorited = false;
    productId = null;
    @track stockInfo = null;
    @track canAddToCart = true;

    connectedCallback() {
        this.extractProductId();
        if (this.productId) {
            this.loadProduct();
        } else {
            this.isLoading = false;
        }
    }

    extractProductId() {
        const url = new URL(window.location.href);
        this.productId = url.searchParams.get('productId');
    }

    loadProduct() {
        this.isLoading = true;

        getProductById({ productId: this.productId })
            .then(result => {
                this.product = result;
                // Check stock
                checkStock({ productId: this.productId })
                    .then(stock => {
                        this.stockInfo = stock;
                        this.canAddToCart = stock.canAddToCart;
                    })
                    .catch(() => { });
                // Track view
                trackProductView({ productId: this.productId }).catch(() => { });

                // Check favorite
                isFavoriteApex({ productId: this.productId })
                    .then(res => { this.isFavorited = res; })
                    .catch(() => { });
                this.loadRelatedProducts();
            })
            .catch(() => {
                this.product = null;
                this.isLoading = false;
            });
    }

    loadRelatedProducts() {
        getRelatedProducts({
            productId: this.productId,
            category: this.product.category,
            maxResults: 8
        })
            .then(result => {
                this.relatedProducts = result.map(p => ({
                    ...p,
                    detailUrl: '/s/product-detail?productId=' + p.id
                }));
                this.isLoading = false;
            })
            .catch(() => {
                this.relatedProducts = [];
                this.isLoading = false;
            });
    }
    get favoriteClass() {
        return this.isFavorited ? 'detail-fav-btn detail-fav-active' : 'detail-fav-btn';
    }
    get hasRelated() {
        return this.relatedProducts.length > 0;
    }
    get stockLabel() {
        if (!this.stockInfo) return '';
        return this.stockInfo.availability;
    }

    get stockClass() {
        if (!this.stockInfo) return '';
        if (this.stockInfo.availability === 'En stock') return 'stock-badge stock-instock';
        if (this.stockInfo.availability === 'Epuise') return 'stock-badge stock-out';
        if (this.stockInfo.availability === 'En arrivage') return 'stock-badge stock-arriving';
        return 'stock-badge stock-order';
    }

    get stockQuantityText() {
        if (!this.stockInfo || this.stockInfo.availability !== 'En stock') return '';
        if (this.stockInfo.stockQuantity <= 5) return this.stockInfo.stockQuantity + ' left - order soon!';
        return this.stockInfo.stockQuantity + ' in stock';
    }

    get addToCartDisabled() {
        return !this.canAddToCart;
    }

    get buyNowDisabled() {
        return !this.canAddToCart;
    }
    handleToggleFavorite() {
        toggleFavorite({ productId: this.productId })
            .then(result => {
                this.isFavorited = result;
            })
            .catch(error => {
                console.error('Favorite error:', error);
            });
    }

    handleRelatedFav(event) {
        event.preventDefault();
        event.stopPropagation();
        const prodId = event.currentTarget.dataset.id;

        toggleFavorite({ productId: prodId })
            .then(() => { })
            .catch(error => {
                console.error('Favorite error:', error);
            });
    }

    incrementQty() {
        this.quantity = this.quantity + 1;
    }

    decrementQty() {
        if (this.quantity > 1) {
            this.quantity = this.quantity - 1;
        }
    }


    handleAddToCart() {
        if (!this.canAddToCart) return;

        if (this.product) {
            for (let i = 0; i < this.quantity; i++) {
                window.dispatchEvent(new CustomEvent('addtocart', {
                    detail: {
                        productId: this.product.id,
                        name: this.product.name,
                        image: this.product.image,
                        unitPrice: this.product.priceNum
                    }
                }));
            }
        }
    }

    handleBuyNow() {
        if (!this.canAddToCart) return;

        this.handleAddToCart();
        window.location.href = '/s/checkout';
    }

    handleRelatedAdd(event) {
        event.preventDefault();
        event.stopPropagation();
        const prodId = event.currentTarget.dataset.id;
        const product = this.relatedProducts.find(p => p.id === prodId);

        if (product) {
            window.dispatchEvent(new CustomEvent('addtocart', {
                detail: {
                    productId: product.id,
                    name: product.name,
                    image: product.image,
                    unitPrice: product.priceNum
                }
            }));
        }
    }
}