import { LightningElement, track, wire } from 'lwc';
import getProfileData from '@salesforce/apex/CkEditProfileController.getProfileData';
import updateProfile from '@salesforce/apex/CkEditProfileController.updateProfile';
import requestEmailChange from '@salesforce/apex/CkEditProfileController.requestEmailChange';
import confirmEmailChange from '@salesforce/apex/CkEditProfileController.confirmEmailChange';
import updatePassword from '@salesforce/apex/CkEditProfileController.updatePassword';
import uploadProfilePhoto from '@salesforce/apex/CkUserController.uploadProfilePhoto';


export default class CkEditProfile extends LightningElement {
    @track isLoading = true;
    @track form = {
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        city: '',
        country: ''
    };

    // Profile
    @track isSavingProfile = false;
    @track profileSuccess = '';
    @track profileError = '';

    // Email
    @track newEmail = '';
    @track emailCode = '';
    @track showEmailCode = false;
    @track isSavingEmail = false;
    @track emailSuccess = '';
    @track emailError = '';

    // Password
    @track oldPassword = '';
    @track newPassword = '';
    @track confirmPassword = '';
    @track isSavingPassword = false;
    @track passwordSuccess = '';
    @track passwordError = '';
    @track showOldPassword = false;
    @track showNewPassword = false;

    // Profile photo    
    @track currentPhoto = '';
    @track showPhotoPreview = false;
    @track tempPhotoUrl = '';
    @track tempPhotoBase64 = '';
    @track tempFileName = '';
    @track photoX = 50;
    @track photoY = 50;
    @track photoZoom = 100;
    @track isUploadingPhoto = false;
    @track photoSuccess = '';
    @track photoError = '';

    @track isSocialUser = false;


    @wire(getProfileData)
    wiredProfile({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.form = {
                firstName: data.firstName || '',
                lastName: data.lastName || '',
                email: data.email || '',
                phone: data.phone || '',
                city: data.city || '',
                country: data.country || ''
            };
            this.currentPhoto = data.photoUrl || ''; 
            this.isSocialUser = data.isSocialUser || false; 


        }
        if (error) {
            this.profileError = 'Failed to load profile data.';
        }
    }

    // ── Password strength ──────────────────────────────────
    get passwordStrength() {
        const p = this.newPassword;
        if (!p) return 'empty';
        if (p.length < 6) return 'weak';
        if (p.length < 10 || !/[A-Z]/.test(p) || !/[0-9]/.test(p)) return 'medium';
        return 'strong';
    }
    get passwordStrengthLabel() {
        const map = { empty: '', weak: 'Weak', medium: 'Medium', strong: 'Strong' };
        return map[this.passwordStrength];
    }
    get strengthBarClass() { return 'ep-strength-fill ' + this.passwordStrength; }
    get strengthLabelClass() { return 'ep-strength-label ' + this.passwordStrength; }

    // ── Toggle password visibility ─────────────────────────
    get oldPasswordType() { return this.showOldPassword ? 'text' : 'password'; }
    get newPasswordType() { return this.showNewPassword ? 'text' : 'password'; }
    toggleOldPassword() { this.showOldPassword = !this.showOldPassword; }
    toggleNewPassword() { this.showNewPassword = !this.showNewPassword; }

    // ── Handlers Profile ───────────────────────────────────
    handleProfileInput(event) {
        const field = event.currentTarget.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        this.profileSuccess = '';
        this.profileError = '';
    }

    handleUpdateProfile() {
        if (!this.form.firstName.trim() || !this.form.lastName.trim()) {
            this.profileError = 'First name and last name are required.';
            return;
        }
        this.isSavingProfile = true;
        this.profileSuccess = '';
        this.profileError = '';

        updateProfile({
            firstName: this.form.firstName,
            lastName: this.form.lastName,
            phone: this.form.phone,
            city: this.form.city,
            country: this.form.country
        })
            .then(() => {
                this.isSavingProfile = false;
                this.profileSuccess = '✓ Profile updated successfully!';
                window.dispatchEvent(new CustomEvent('profileUpdated'));

                setTimeout(() => { this.profileSuccess = ''; }, 4000);
            })
            .catch(error => {
                this.isSavingProfile = false;
                this.profileError = error.body ? error.body.message : 'Failed to update profile.';
            });
    }

    // ── Handlers Email ─────────────────────────────────────
    handleNewEmailInput(event) { this.newEmail = event.target.value; this.emailError = ''; }
    handleEmailCodeInput(event) { this.emailCode = event.target.value; this.emailError = ''; }

    handleRequestEmailChange() {
        if (!this.newEmail || !this.newEmail.includes('@')) {
            this.emailError = 'Please enter a valid email address.';
            return;
        }
        if (this.newEmail === this.form.email) {
            this.emailError = 'New email must be different from current email.';
            return;
        }
        this.isSavingEmail = true;
        this.emailError = '';

        requestEmailChange({ newEmail: this.newEmail })
            .then(() => {
                this.isSavingEmail = false;
                this.showEmailCode = true;
                this.emailSuccess = 'Verification code sent to ' + this.newEmail;
            })
            .catch(error => {
                this.isSavingEmail = false;
                this.emailError = error.body ? error.body.message : 'Failed to send code.';
            });
    }

    handleConfirmEmailChange() {
        if (!this.emailCode || this.emailCode.length !== 6) {
            this.emailError = 'Please enter the 6-digit code.';
            return;
        }
        this.isSavingEmail = true;
        this.emailError = '';

        confirmEmailChange({ code: this.emailCode })
            .then(() => {
                this.isSavingEmail = false;
                this.showEmailCode = false;
                this.form = { ...this.form, email: this.newEmail };
                this.newEmail = '';
                this.emailCode = '';
                this.emailSuccess = '✓ Email updated successfully!';
                window.dispatchEvent(new CustomEvent('profileUpdated'));

                setTimeout(() => { this.emailSuccess = ''; }, 4000);
            })
            .catch(error => {
                this.isSavingEmail = false;
                this.emailError = error.body ? error.body.message : 'Verification failed.';
            });
    }

    cancelEmailChange() {
        this.showEmailCode = false;
        this.newEmail = '';
        this.emailCode = '';
        this.emailError = '';
        this.emailSuccess = '';
    }

    // ── Handlers Password ──────────────────────────────────
    handleOldPasswordInput(event) { this.oldPassword = event.target.value; this.passwordError = ''; }
    handleNewPasswordInput(event) { this.newPassword = event.target.value; this.passwordError = ''; }
    handleConfirmPasswordInput(event) { this.confirmPassword = event.target.value; this.passwordError = ''; }

    handleUpdatePassword() {
        if (!this.oldPassword) {
            this.passwordError = 'Please enter your current password.';
            return;
        }
        if (this.newPassword.length < 8) {
            this.passwordError = 'New password must be at least 8 characters.';
            return;
        }
        if (this.newPassword !== this.confirmPassword) {
            this.passwordError = 'Passwords do not match.';
            return;
        }
        if (this.newPassword === this.oldPassword) {
            this.passwordError = 'New password must be different from current password.';
            return;
        }

        this.isSavingPassword = true;
        this.passwordError = '';

        updatePassword({
            oldPassword: this.oldPassword,
            newPassword: this.newPassword
        })
            .then(() => {
                this.isSavingPassword = false;
                this.oldPassword = '';
                this.newPassword = '';
                this.confirmPassword = '';
                this.passwordSuccess = '✓ Password updated successfully!';
                setTimeout(() => { this.passwordSuccess = ''; }, 4000);
            })
            .catch(error => {
                this.isSavingPassword = false;
                this.passwordError = error.body ? error.body.message : 'Failed to update password.';
            });
    }
    triggerPhotoUpload() {
        const input = this.template.querySelector('[data-id="photoInput"]');
        if (input) input.click();
    }

    handlePhotoSelect(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (file.size > 2 * 1024 * 1024) {
            this.photoError = 'Image must be less than 2MB.';
            return;
        }
        if (!file.type.startsWith('image/')) {
            this.photoError = 'Please select an image file.';
            return;
        }
        this.tempFileName = file.name;
        this.photoError = '';

        const reader = new FileReader();
        reader.onload = () => {
            this.tempPhotoUrl = reader.result;
            this.tempPhotoBase64 = reader.result.split(',')[1];
            this.photoX = 50;
            this.photoY = 50;
            this.photoZoom = 100;
            this.showPhotoPreview = true;
        };
        reader.readAsDataURL(file);
    }

    movePhoto(event) {
        const dir = event.currentTarget.dataset.dir;
        const step = 5;
        if (dir === 'up') this.photoY = Math.max(0, this.photoY - step);
        if (dir === 'down') this.photoY = Math.min(100, this.photoY + step);
        if (dir === 'left') this.photoX = Math.max(0, this.photoX - step);
        if (dir === 'right') this.photoX = Math.min(100, this.photoX + step);
        this.updatePreviewStyle();
    }

    resetPhotoPosition() {
        this.photoX = 50; this.photoY = 50; this.photoZoom = 100;
        this.updatePreviewStyle();
    }

    handleZoom(event) {
        this.photoZoom = parseInt(event.target.value, 10);
        this.updatePreviewStyle();
    }

    updatePreviewStyle() {
        const img = this.template.querySelector('[data-id="previewImg"]');
        if (img) {
            img.style.objectPosition = this.photoX + '% ' + this.photoY + '%';
            img.style.transform = 'scale(' + (this.photoZoom / 100) + ')';
        }
    }

    cancelPhotoEdit() {
        this.showPhotoPreview = false;
        this.tempPhotoUrl = '';
        this.tempPhotoBase64 = '';
        this.photoError = '';
    }

    handleSavePhoto() {
        this.isUploadingPhoto = true;
        this.photoError = '';

        // Récupérer contactId
        getProfileData()
            .then(data => {
                return uploadProfilePhoto({
                    fileName: this.tempFileName,
                    base64Data: this.tempPhotoBase64,
                    contactId: data.contactId
                });
            })
            .then(photoUrl => {
                this.isUploadingPhoto = false;
                this.currentPhoto = photoUrl;
                this.showPhotoPreview = false;
                this.tempPhotoUrl = '';
                this.tempPhotoBase64 = '';
                this.photoSuccess = '✓ Photo updated successfully!';
                window.dispatchEvent(new CustomEvent('profileUpdated'));

                setTimeout(() => { this.photoSuccess = ''; }, 4000);
            })
            .catch(error => {
                this.isUploadingPhoto = false;
                this.photoError = error.body ? error.body.message : 'Failed to upload photo.';
            });
    }
}