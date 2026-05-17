import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getUserContext from "@salesforce/apex/CkLoginRedirectController.getUserContext";
import basePath from "@salesforce/community/basePath";

export default class CkLoginRedirect extends NavigationMixin(LightningElement) {
  isLoading = true;
  accountType;
  firstName;
  errorMessage;
  hasRedirected = false;

  @wire(getUserContext)
  wiredUserContext({ error, data }) {
    if (data) {
      this.accountType = data.accountType;
      this.firstName = data.firstName;

      // Trigger redirect only if needed and only once
      if (data.shouldRedirect && data.redirectPage && !this.hasRedirected) {
        this.hasRedirected = true;
        this.redirectToPage(data.redirectPage);
      } else {
        // Nothing to do — hide the spinner immediately
        this.isLoading = false;
      }
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error("ckLoginRedirect error:", error);
      this.errorMessage = "Unable to verify user context.";
      this.isLoading = false;
    }
  }

  redirectToPage(pageName) {
    // Use direct URL navigation — more reliable than comm__namedPage
    // basePath = "/TalFlowExpress/s" in Experience Cloud
    const targetUrl = `${basePath}/${pageName}`;

    // eslint-disable-next-line no-console
    console.log("🎯 ckLoginRedirect → navigating to:", targetUrl);

    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: targetUrl
      }
    });
  }
}
