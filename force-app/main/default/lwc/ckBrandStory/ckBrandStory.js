import { LightningElement, api } from 'lwc';

export default class CkBrandStory extends LightningElement {
    @api eyebrow = 'Est. 2026';
    @api title = 'Meet TalFlow Express.';
    @api description = '';
    @api buttonText = 'Explore Our Collection →';
    @api buttonUrl = '/shop';
    @api imageUrl = '';

    defaultDescription = "We started with one belief: great technology shouldn't be complicated or overpriced. TalFlow Express is built for people who value quality, simplicity, and innovation in their everyday tech. From smart accessories to cutting-edge gadgets, every product we curate is handpicked to deliver real performance — no gimmicks, no compromises. We're not just selling tech. We're shaping how you experience it.";

    get displayDescription() {
        return this.description || this.defaultDescription;
    }

    get displayImage() {
        return this.imageUrl || '/sfsites/c/resource/TalFlowExpressBanniere';
    }
}