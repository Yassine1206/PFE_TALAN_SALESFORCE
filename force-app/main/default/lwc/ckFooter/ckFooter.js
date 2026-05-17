import { LightningElement, wire, track } from "lwc";
import getFooterData from "@salesforce/apex/CkFooterController.getFooterData";
import subscribe from "@salesforce/apex/CkNewsletterController.subscribe";

export default class CkFooter extends LightningElement {
  @track brand = {};
  @track shopLinks = [];
  @track aboutLinks = [];
  @track supportLinks = [];

  emailValue = "";
  isSubmitting = false;
  feedbackMessage = "";
  feedbackType = "";

  @wire(getFooterData)
  wiredFooter({ data, error }) {
    if (data) {
      this.brand = data.brand || {};
      this.shopLinks = this.enrichLinks(data.shopLinks);
      this.aboutLinks = this.enrichLinks(data.aboutLinks);
      this.supportLinks = this.enrichLinks(data.supportLinks);
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("CkFooter error:", error);
    }
  }

  // Pre-compute target attribute for each link
  enrichLinks(links) {
    if (!links) return [];
    return links.map((link) => ({
      ...link,
      target: link.Open_In_New_Tab__c ? "_blank" : "_self"
    }));
  }

  // ═══ Brand getters ═══
  get logoUrl() {
    const resourceName = this.brand?.Logo_Static_Resource__c || "talflow_logo";
    return `/sfsites/c/resource/${resourceName}`;
  }

  get brandAltText() {
    return this.brand?.Logo_Alt_Text__c || "TalFlow Express";
  }
  get tagline() {
    return this.brand?.Tagline__c || "";
  }
  get copyrightText() {
    return this.brand?.Copyright_Text__c || "";
  }
  get instagramUrl() {
    return this.brand?.Instagram_URL__c || "";
  }
  get xUrl() {
    return this.brand?.X_URL__c || "";
  }
  get tiktokUrl() {
    return this.brand?.Tiktok_URL__c || "";
  }
  get privacyUrl() {
    return this.brand?.Privacy_Policy_URL__c || "";
  }
  get termsUrl() {
    return this.brand?.Terms_URL__c || "";
  }
  get cookieUrl() {
    return this.brand?.Cookie_URL__c || "";
  }
  get newsletterTitle() {
    return this.brand?.Newsletter_Title__c || "Stay in the loop";
  }
  get newsletterDescription() {
    return this.brand?.Newsletter_Description__c || "";
  }

  // ═══ Newsletter ═══
  handleEmailInput(event) {
    this.emailValue = event.target.value;
    this.feedbackMessage = "";
  }

  handleKeyDown(event) {
    if (event.key === "Enter") {
      this.handleSubscribe();
    }
  }

  handleSubscribe() {
    if (this.isSubmitting) return;

    const email = this.emailValue.trim();
    if (!email) {
      this.showFeedback("Please enter your email.", "error");
      return;
    }

    this.isSubmitting = true;
    this.feedbackMessage = "";

    subscribe({ email })
      .then((message) => {
        this.isSubmitting = false;
        this.emailValue = "";
        this.showFeedback(message, "success");
      })
      .catch((error) => {
        this.isSubmitting = false;
        const msg =
          error?.body?.message || "Subscription failed. Please try again.";
        this.showFeedback(msg, "error");
      });
  }

  showFeedback(message, type) {
    this.feedbackMessage = message;
    this.feedbackType = type;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      if (this.feedbackMessage === message) {
        this.feedbackMessage = "";
      }
    }, 5000);
  }

  get feedbackClass() {
    return this.feedbackType === "error"
      ? "ck-footer-feedback ck-footer-feedback-error"
      : "ck-footer-feedback ck-footer-feedback-success";
  }
}
