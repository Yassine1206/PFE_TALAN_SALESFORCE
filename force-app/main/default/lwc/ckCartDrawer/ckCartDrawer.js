import { LightningElement, track } from 'lwc';
import getCart from '@salesforce/apex/CkCartController.getCart';
import addToCartApex from '@salesforce/apex/CkCartController.addToCart';
import updateQuantityApex from '@salesforce/apex/CkCartController.updateQuantity';
import removeItemApex from '@salesforce/apex/CkCartController.removeItem';

export default class CkCartDrawer extends LightningElement {
    @track isOpen = false;
    @track cartItems = [];
    @track isGuest = true;
    @track isLoading = false;
    @track guestCart = [];

    _guestIdCounter = 0;
    _boundHandleAddToCart = null;

    connectedCallback() {
        this.loadCart();
        this._boundHandleAddToCart = this.handleAddToCartEvent.bind(this);
        window.addEventListener('addtocart', this._boundHandleAddToCart);
        this._cartUpdatedHandler = this.loadCart.bind(this);
        window.addEventListener('cartUpdated', this._cartUpdatedHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('addtocart', this._boundHandleAddToCart);
        this._boundHandleAddToCart = null;
        window.removeEventListener('cartUpdated', this._cartUpdatedHandler);

    }

    loadCart() {
        getCart()
            .then(result => {
                this.isGuest = result.isGuest === true;

                if (!this.isGuest && result.items) {
                    this.cartItems = result.items.map(item => ({
                        id: item.itemId,
                        productId: item.productId,
                        name: item.name || '',
                        image: item.image || '',
                        price: '$' + (item.unitPrice != null ? item.unitPrice : 0).toFixed(2),
                        priceNum: item.unitPrice != null ? item.unitPrice : 0,
                        quantity: item.quantity != null ? item.quantity : 1,
                        lineTotal: item.lineTotal != null ? item.lineTotal : 0
                    }));
                } else if (this.isGuest) {
                    this.cartItems = [...this.guestCart];
                }
            })
            .catch(error => {
                console.error('loadCart error:', error);
                this.isGuest = true;
                this.cartItems = [...this.guestCart];
            });
    }

    // handleAddToCartEvent(event) {
    //     const product = event.detail;
    //     if (!product || !product.productId) return;
    //     this.addToCart({
    //         productId: product.productId,
    //         name: product.name || '',
    //         image: product.image || '',
    //         unitPrice: product.unitPrice != null ? Number(product.unitPrice) : 0
    //     });
    // }
    handleAddToCartEvent(event) {
        const product = event.detail;
        console.log('product recu:', JSON.stringify({
            productId: product.productId,
            name: product.name,
            unitPrice: product.unitPrice,
            image: product.image
        }));

        if (!product || !product.productId) return;

        this.addToCart({
            productId: product.productId,
            name: product.name || '',
            image: product.image || '',
            unitPrice: product.unitPrice != null ? Number(product.unitPrice) : 0
        });
    }

    addToCart(product) {
        if (this.isGuest) {
            const existing = this.guestCart.find(item => item.productId === product.productId);
            if (existing) {
                existing.quantity += 1;
                this.guestCart = [...this.guestCart];
            } else {
                this._guestIdCounter += 1;
                const unitPrice = product.unitPrice != null ? product.unitPrice : 0;
                this.guestCart = [...this.guestCart, {
                    id: 'guest_' + this._guestIdCounter,
                    productId: product.productId,
                    name: product.name || '',
                    image: product.image || '',
                    price: '$' + unitPrice.toFixed(2),
                    priceNum: unitPrice,
                    quantity: 1
                }];
            }
            this.cartItems = [...this.guestCart];
            this.isOpen = true;

        } else {
            this.isLoading = true;
            addToCartApex({
                productId: product.productId,
                productName: product.name,
                productImage: product.image,
                unitPrice: product.unitPrice
            })
                .then(item => {
                    this.isLoading = false;
                    this.loadCart();
                    this.isOpen = true;
                })
                .catch(error => {
                    this.isLoading = false;
                    console.error('Add to cart error:', error);
                });
        }
    }

    get hasItems() {
        return this.cartItems.length > 0;
    }

    get itemCount() {
        return this.cartItems.reduce((sum, item) => sum + (item.quantity || 0), 0);
    }

    get subtotal() {
        const total = this.cartItems.reduce((sum, item) =>
            sum + ((item.priceNum || 0) * (item.quantity || 0)), 0);
        return '$' + total.toFixed(2);
    }

    get drawerClass() {
        return this.isOpen ? 'cart-drawer cart-drawer-open' : 'cart-drawer';
    }

    get buttonStyle() {
        return this.hideButton ? 'display:none' : '';
    }

    toggleCart() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) this.loadCart();
    }

    closeCart() {
        this.isOpen = false;
    }

    updateQty(event) {
        const itemId = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;

        const item = this.cartItems.find(i => i.id === itemId);
        if (!item) return;

        const newQty = action === 'plus'
            ? item.quantity + 1
            : Math.max(1, item.quantity - 1);

        if (this.isGuest) {
            const guestItem = this.guestCart.find(i => i.id === itemId);
            if (guestItem) {
                guestItem.quantity = newQty;
                this.guestCart = [...this.guestCart];
                this.cartItems = [...this.guestCart];
            }
        } else {
            updateQuantityApex({ itemId, quantity: newQty })
                .then(() => this.loadCart())
                .catch(error => console.error('Update qty error:', error));
        }
    }

    removeItem(event) {
        const itemId = event.currentTarget.dataset.id;

        if (this.isGuest) {
            this.guestCart = this.guestCart.filter(i => i.id !== itemId);
            this.cartItems = [...this.guestCart];
        } else {
            removeItemApex({ itemId })
                .then(() => this.loadCart())
                .catch(error => console.error('Remove item error:', error));
        }
    }
}