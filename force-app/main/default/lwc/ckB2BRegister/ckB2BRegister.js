import { LightningElement, track } from 'lwc';
import registerB2B from '@salesforce/apex/CkRegistrationController.registerB2B';

export default class CkB2BRegister extends LightningElement {
    @track currentStep = 1;
    @track isLoading = false;
    @track isSuccess = false;
    @track errorMessage = '';
    @track termsAccepted = false;
    @track showPassword = false;

    @track form = {
        // Step 1 — Company
        companyName: '',
        industry: '',
        numberOfEmployees: '',
        website: '',
        annualRevenue: '',
        city: '',
        country: '',
        description: '',
        // Step 2 — Contact
        firstName: '',
        lastName: '',
        title: '',
        email: '',
        phone: '',
        // Step 3 — Account
        password: '',
        confirmPassword: ''
    };

    // ── Getters steps ──
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }

    get stepClass1() { return this.currentStep > 1 ? 'b2b-step done' : 'b2b-step active'; }
    get stepClass2() {
        if (this.currentStep > 2) return 'b2b-step done';
        if (this.currentStep === 2) return 'b2b-step active';
        return 'b2b-step';
    }
    get stepClass3() { return this.currentStep === 3 ? 'b2b-step active' : 'b2b-step'; }

    get fullName() {
        return (this.form.firstName + ' ' + this.form.lastName).trim();
    }

    get passwordType() { return this.showPassword ? 'text' : 'password'; }

    // ── Password strength ──
    get passwordStrength() {
        const p = this.form.password;
        if (!p) return 'empty';
        if (p.length < 6) return 'weak';
        if (p.length < 10 || !/[A-Z]/.test(p) || !/[0-9]/.test(p)) return 'medium';
        return 'strong';
    }

    get passwordStrengthLabel() {
        const map = { empty: '', weak: 'Weak', medium: 'Medium', strong: 'Strong' };
        return map[this.passwordStrength];
    }

    get strengthBarClass() {
        return 'b2b-strength-fill ' + this.passwordStrength;
    }

    get strengthLabelClass() {
        return 'b2b-strength-label ' + this.passwordStrength;
    }

    // ── Handlers ──
    handleInput(event) {
        const field = event.currentTarget.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        this.errorMessage = '';
    }

    handleTerms(event) {
        this.termsAccepted = event.target.checked;
    }

    togglePassword() {
        this.showPassword = !this.showPassword;
    }

    // ── Validation ──
    validateStep1() {
        if (!this.form.companyName.trim()) {
            this.errorMessage = 'Company name is required.'; return false;
        }
        if (!this.form.industry) {
            this.errorMessage = 'Please select an industry.'; return false;
        }
        if (!this.form.numberOfEmployees) {
            this.errorMessage = 'Please select company size.'; return false;
        }
        if (!this.form.city.trim()) {
            this.errorMessage = 'City is required.'; return false;
        }
        if (!this.form.country) {
            this.errorMessage = 'Please select a country.'; return false;
        }
        return true;
    }

    validateStep2() {
        if (!this.form.firstName.trim()) {
            this.errorMessage = 'First name is required.'; return false;
        }
        if (!this.form.lastName.trim()) {
            this.errorMessage = 'Last name is required.'; return false;
        }
        if (!this.form.title.trim()) {
            this.errorMessage = 'Job title is required.'; return false;
        }
        if (!this.form.email.trim() || !this.form.email.includes('@')) {
            this.errorMessage = 'Please enter a valid email.'; return false;
        }
        if (!this.form.phone.trim()) {
            this.errorMessage = 'Phone number is required.'; return false;
        }
        return true;
    }

    validateStep3() {
        if (this.form.password.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.'; return false;
        }
        if (this.form.password !== this.form.confirmPassword) {
            this.errorMessage = 'Passwords do not match.'; return false;
        }
        if (!this.termsAccepted) {
            this.errorMessage = 'Please accept the Terms of Service.'; return false;
        }
        return true;
    }

    nextStep() {
        this.errorMessage = '';
        if (this.currentStep === 1 && !this.validateStep1()) return;
        if (this.currentStep === 2 && !this.validateStep2()) return;
        this.currentStep++;
    }

    prevStep() {
        this.errorMessage = '';
        this.currentStep--;
    }

    // ── Submit ──
    handleSubmit() {
        this.errorMessage = '';
        if (!this.validateStep3()) return;

        this.isLoading = true;

        registerB2B({
            companyName: this.form.companyName,
            firstName: this.form.firstName,
            lastName: this.form.lastName,
            email: this.form.email,
            phone: this.form.phone,
            title: this.form.title,
            industry: this.form.industry,
            numberOfEmployees: parseInt(this.form.numberOfEmployees, 10),
            website: this.form.website || '',
            annualRevenue: this.form.annualRevenue
                ? parseFloat(this.form.annualRevenue) : null,
            city: this.form.city,
            country: this.form.country,
            description: this.form.description || '',
            password: this.form.password
        })
            .then(() => {
                this.isLoading = false;
                this.isSuccess = true;
                this.currentStep = 4;
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = error.body ? error.body.message : 'An error occurred.';
            });
    }
}