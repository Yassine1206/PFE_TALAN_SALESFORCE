import { LightningElement, wire } from "lwc";
import getActiveHero from "@salesforce/apex/CkHeroController.getActiveHero";

export default class CkHero extends LightningElement {
  hero;
  isLoading = true;
  error;

  @wire(getActiveHero)
  wiredHero({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.hero = data;
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.hero = undefined;
      // eslint-disable-next-line no-console
      console.error("CkHero error:", error);
    }
  }
}
