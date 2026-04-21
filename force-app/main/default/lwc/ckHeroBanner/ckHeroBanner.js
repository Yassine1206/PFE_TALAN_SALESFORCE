import { LightningElement, api } from 'lwc';

export default class CkHeroBanner extends LightningElement {
    @api title = 'CloudKicks';
    @api subtitle = 'Step into the future of comfort. Engineered for the streets, designed for the clouds.';
    @api ctaLabel = 'Shop the Drop';
    @api ctaUrl = '/shop';
    @api badgeText = 'New Drop Available';
    @api backgroundImage = '/sfsites/c/resource/ckHeroBg';
}
