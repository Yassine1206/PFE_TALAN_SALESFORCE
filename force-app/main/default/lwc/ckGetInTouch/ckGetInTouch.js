import { LightningElement, track } from "lwc";
import submitContactForm from "@salesforce/apex/CkGetInTouchController.submitContactForm";
import isGuest from "@salesforce/user/isGuest";

const SUBJECTS = [
  { value: "General Inquiry", label: "General Inquiry" },
  { value: "Order Issue", label: "Order Issue" },
  { value: "Product Question", label: "Product Question" },
  { value: "Billing", label: "Billing" },
  { value: "Other", label: "Other" }
];

export default class CkGetInTouch extends LightningElement {
  @track firstName = "";
  @track lastName = "";
  @track email = "";
  @track phone = "";
  @track subject = "General Inquiry";
  @track message = "";

  @track isSubmitting = false;
  @track successMessage = "";
  @track errorMessage = "";

  subjectOptions = SUBJECTS;

  get isGuestUser() {
    return isGuest;
  }

  get showThankYou() {
    return this.successMessage.length > 0;
  }

  handleInput(event) {
    const field = event.target.dataset.field;
    if (field) {
      this[field] = event.target.value;
    }
  }

  handleSubjectChange(event) {
    this.subject = event.target.value;
  }

  async handleSubmit() {
    this.errorMessage = "";
    this.successMessage = "";

    // Validation
    if (!this.message.trim()) {
      this.errorMessage = "Please enter a message.";
      return;
    }
    if (this.isGuestUser) {
      if (
        !this.firstName.trim() ||
        !this.lastName.trim() ||
        !this.email.trim()
      ) {
        this.errorMessage = "Please fill your name and email.";
        return;
      }
      if (!this.email.includes("@")) {
        this.errorMessage = "Please enter a valid email.";
        return;
      }
    }

    this.isSubmitting = true;

    try {
      const result = await submitContactForm({
        firstName: this.firstName,
        lastName: this.lastName,
        email: this.email,
        phone: this.phone,
        subject: this.subject,
        message: this.message
      });

      if (result.success) {
        this.successMessage = result.message;
        this.firstName = "";
        this.lastName = "";
        this.email = "";
        this.phone = "";
        this.message = "";
        this.subject = "General Inquiry";
      } else {
        this.errorMessage = result.message || "Failed to send.";
      }
    } catch (error) {
      this.errorMessage = error.body ? error.body.message : "Failed to send.";
    } finally {
      this.isSubmitting = false;
    }
  }

  handleNewMessage() {
    this.successMessage = "";
    this.errorMessage = "";
  }

  get submitButtonLabel() {
    return this.isSubmitting ? "Sending..." : "Send Message";
  }
}
