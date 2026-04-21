import { LightningElement, api } from 'lwc';
import basePath from '@salesforce/community/basePath';

export default class CkProductCard extends LightningElement {
    // Required
    @api productId;
    @api name = '';
    @api imageUrl = '';
    @api price = 0;

    // Optional — displayed if provided
    @api oldPrice;
    @api category = '';
    @api rating;
    @api description = '';
    @api availability = '';
    @api isOnSale = false;
    @api discountPercent = 0;
    @api isNew = false;
    @api isOutOfStock = false;

    // Display toggles — parent controls what to show
    @api showCategory = false;
    @api showRating = false;
    @api showDesc = false;
    @api showAvail = false;
    @api compact = false; // true = minimal card (carousel), false = full card (category page)

    @api variant = 'default'; // 'default' | 'hotdeal' | 'bestseller'

    // ═══ Getters ═══
    get cardClass() {
        const base = 'ck-card';
        if (this.variant === 'hotdeal') return base + ' ck-card-hotdeal';
        if (this.variant === 'bestseller') return base + ' ck-card-bestseller';
        return base;
    }

    get showRibbon() {
        return this.variant === 'hotdeal' && this.isOnSale;
    }

    get detailUrl() {
        return basePath + '/product-detail?productId=' + this.productId;
    }

    get formattedPrice() {
        const p = Number(this.price);
        return isNaN(p) ? '$0.00' : '$' + p.toFixed(2);
    }

    get formattedOldPrice() {
        if (!this.oldPrice) return '';
        const p = Number(this.oldPrice);
        return isNaN(p) ? '' : '$' + p.toFixed(2);
    }

    get safeImage() {
        return this.imageUrl && this.imageUrl.startsWith('http')
            ? this.imageUrl
            : 'https://images.unsplash.com/photo-1663465376645-aca0b7c8227a?q=80&w=880&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D';
    }

    get shortDescription() {
        if (!this.description) return '';
        return this.description.length > 60
            ? this.description.substring(0, 60) + '...'
            : this.description;
    }

    get showMeta() {
        return (this.showCategory && this.category) || (this.showRating && this.rating);
    }

    get showDescription() {
        return this.showDesc && this.description;
    }

    get showAvailability() {
        return this.showAvail && this.availability;
    }

    get availabilityClass() {
        if (this.isOutOfStock) return 'ck-avail ck-avail-out';
        if (this.availability === 'En stock') return 'ck-avail ck-avail-in';
        return 'ck-avail ck-avail-order';
    }
    get priceClass() {
        return this.variant === 'hotdeal' ? 'ck-price-current ck-price-hot' : 'ck-price-current';
    }
    handleAddToCart(event) {
        event.preventDefault();
        event.stopPropagation();

        if (this.isOutOfStock) return;

        // Même pattern que ckProductDetail
        // Dispatch direct sur window → ckCartDrawer reçoit une seule fois
        window.dispatchEvent(new CustomEvent('addtocart', {
            detail: {
                productId: this.productId,
                name: this.name,
                image: this.imageUrl,
                unitPrice: this.price  // priceNum passé par le parent via price={item.priceNum}
            }
        }));
    }
    handleViewDetails(event) {
        event.preventDefault();
        event.stopPropagation();
        window.location.href = this.detailUrl;
    }
}