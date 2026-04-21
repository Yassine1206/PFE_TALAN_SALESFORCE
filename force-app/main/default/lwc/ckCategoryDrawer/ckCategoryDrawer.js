import { LightningElement, track, wire } from 'lwc';
import getCategoriesWithSubs from '@salesforce/apex/CkProductController.getCategoriesWithSubs';
import basePath from '@salesforce/community/basePath';


export default class CkCategoryDrawer extends LightningElement {
    @track categories = [];
    @track isOpen = false;
    @track expandedCat = null;

    @wire(getCategoriesWithSubs)
    wiredCats({ data }) {
        if (data) {
            this.categories = data.map(cat => ({
                ...cat,
                isExpanded: false,
                hasSubs: cat.subcategories && cat.subcategories.length > 0,
                searchUrl: '/s/search-results?q=' + encodeURIComponent(cat.name)
            }));
        }
    }

    connectedCallback() {
        window.addEventListener('togglecategorydrawer', () => this.toggleDrawer());
    }

    disconnectedCallback() {
        window.removeEventListener('togglecategorydrawer', () => this.toggleDrawer());
    }

    toggleDrawer() {
        this.isOpen = !this.isOpen;
    }

    closeDrawer() {
        this.isOpen = false;
    }

    handleOverlayClick() {
        this.closeDrawer();
    }

    handleToggleCategory(event) {
        const catName = event.currentTarget.dataset.cat;
        this.categories = this.categories.map(cat => ({
            ...cat,
            isExpanded: cat.name === catName ? !cat.isExpanded : false
        }));
    }

    handleCategoryClick(event) {
        const catName = event.currentTarget.dataset.cat;
        window.location.href = basePath + '/category?cat=' + encodeURIComponent(catName);
    }

    handleSubClick(event) {
        event.stopPropagation();
        const sub = event.currentTarget.dataset.sub;
        const cat = event.currentTarget.dataset.cat;
        window.location.href = basePath + '/category?cat=' + encodeURIComponent(cat) + '&sub=' + encodeURIComponent(sub);
    }

    handleOpenBtn() {
        this.toggleDrawer();
    }

    get drawerClass() {
        return this.isOpen ? 'cd-drawer cd-drawer-open' : 'cd-drawer';
    }

    get overlayClass() {
        return this.isOpen ? 'cd-overlay cd-overlay-visible' : 'cd-overlay';
    }
}