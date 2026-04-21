import { LightningElement, track, wire } from 'lwc';
import getUserDetails from '@salesforce/apex/CkUserController.getUserDetails';
import registerB2C from '@salesforce/apex/CkRegistrationController.registerB2C';
import registerB2B from '@salesforce/apex/CkRegistrationController.registerB2B';
import loginUser from '@salesforce/apex/CkRegistrationController.loginUser';
import verifyEmail from '@salesforce/apex/CkRegistrationController.verifyEmail';
import resendVerificationCode from '@salesforce/apex/CkRegistrationController.resendVerificationCode';
import forgotPassword from '@salesforce/apex/CkRegistrationController.forgotPassword';
import uploadProfilePhoto from '@salesforce/apex/CkUserController.uploadProfilePhoto';
import { refreshApex } from '@salesforce/apex'; // ← ajouter

export default class CkAuthModal extends LightningElement {
    @track showModal = false;
    @track currentStep = 'choice';
    @track errorMessage = '';
    @track successMessage = '';
    @track isLoading = false;
    @track userData = null;
    @track isLoggedIn = false;
    @track isUploadingPhoto = false;

    // Verification
    @track verificationEmail = '';
    @track verificationCode = '';
    @track verificationMessage = '';
    @track verificationError = '';
    @track isVerifying = false;

    // Forgot Password
    @track forgotEmail = '';
    @track forgotMessage = '';
    @track forgotError = '';
    @track isSendingReset = false;

    // Photo editor
    @track showPhotoEditor = false;
    @track tempPhotoUrl = '';
    @track tempPhotoBase64 = '';
    @track tempFileName = '';
    @track photoX = 50;
    @track photoY = 50;
    @track photoZoom = 100;

    _wiredUserResult; // ← ajouter

    @wire(getUserDetails)
    wiredUser(result) {
        this._wiredUserResult = result; // ← stocker le result
        const { data, error } = result;

        if (data) {
            if (data.isAuthenticated) {
                this.isLoggedIn = true;
                this.userData = data;
            } else {
                this.isLoggedIn = false;
                this.userData = null;
            }
        }
        if (error) {
            this.isLoggedIn = false;
            this.userData = null;
        }
    }

    // ═══ Getters - User Data ═══
    get userFullName() { return this.userData ? this.userData.fullName : ''; }
    get userEmail() { return this.userData ? this.userData.email : ''; }
    get userPhone() { return this.userData ? this.userData.phone : ''; }
    get userPhoto() { return this.userData ? this.userData.photoUrl : ''; }
    get userProfileName() { return this.userData ? this.userData.profileName : ''; }
    get userCompany() { return this.userData ? this.userData.companyName : ''; }
    get userMemberSince() { return this.userData ? this.userData.memberSince : ''; }
    get userContactId() { return this.userData ? this.userData.contactId : ''; }
    get showUserPhoto() { return this.isLoggedIn && this.userData && this.userData.photoUrl; }

    // ═══ Getters - Steps ═══
    get isProfileStep() { return this.currentStep === 'profile'; }
    get isChoiceStep() { return this.currentStep === 'choice'; }
    get isSignInStep() { return this.currentStep === 'signin'; }
    get isAccountTypeStep() { return this.currentStep === 'accounttype'; }
    get isRegisterB2CStep() { return this.currentStep === 'registerb2c'; }
    get isRegisterB2BStep() { return this.currentStep === 'registerb2b'; }
    get isSuccessStep() { return this.currentStep === 'success'; }
    get isConfirmLogoutStep() { return this.currentStep === 'confirmlogout'; }
    get isLoggingOutStep() { return this.currentStep === 'loggingout'; }
    get isVerifyStep() { return this.currentStep === 'verify'; }
    get isForgotStep() { return this.currentStep === 'forgot'; }

    // ═══ Photo editor getters ═══
    get editorPositionStyle() {
        return `object-position: ${this.photoX}% ${this.photoY}%; transform: scale(${this.photoZoom / 100});`;
    }

    // ═══ Modal Controls ═══
    handleProfileClick() {
        this.showModal = true;
        this.errorMessage = '';
        this.successMessage = '';
        this.verificationMessage = '';
        this.verificationError = '';
        this.forgotMessage = '';
        this.forgotError = '';

        if (this.isLoggedIn) {
            this.currentStep = 'profile';
        } else {
            this.currentStep = 'choice';
        }
    }
    handleEditProfile() {
        this.closeModal();
        window.location.href = '/TalFlowExpress/s/edit-profile';
    }

    closeModal() {
        this.showModal = false;
        this.errorMessage = '';
        this.successMessage = '';
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    // ═══ Navigation ═══
    showChoice() { this.currentStep = 'choice'; this.errorMessage = ''; }
    showSignIn() { this.currentStep = 'signin'; this.errorMessage = ''; }
    showAccountType() { this.currentStep = 'accounttype'; this.errorMessage = ''; }
    selectB2C() { this.currentStep = 'registerb2c'; this.errorMessage = ''; }
    selectB2B() {
        // this.currentStep = 'registerb2b'; this.errorMessage = '';
        this.closeModal();
        window.location.href = '/TalFlowExpress/s/register-b2b';
    }

    handleBackToSignIn() {
        this.currentStep = 'signin';
        this.errorMessage = '';
        this.verificationMessage = '';
        this.verificationError = '';
        this.verificationCode = '';
        this.forgotMessage = '';
        this.forgotError = '';
    }

    // ═══ Sign In ═══
    handleSignIn() {
        const email = this.template.querySelector('[data-id="loginEmail"]');
        const password = this.template.querySelector('[data-id="loginPassword"]');

        if (!email || !email.value || !password || !password.value) {
            this.errorMessage = 'Please fill in all fields.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        loginUser({
            username: email.value,
            password: password.value,
            startUrl: '/TalFlowExpress/s/'
        })
            .then(result => {
                this.isLoading = false;
                if (result && result.startsWith('VERIFY:')) {
                    this.verificationEmail = result.replace('VERIFY:', '');
                    this.currentStep = 'verify';
                    this.verificationMessage = 'Please verify your email first. A new code has been sent.';
                } else if (result) {
                    window.location.href = result;
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = error.body ? error.body.message : 'Invalid email or password. Please try again.';
            });
    }

    // ═══ Register B2C ═══
    handleRegisterB2C() {
        const firstName = this.template.querySelector('[data-id="b2cFirstName"]');
        const lastName = this.template.querySelector('[data-id="b2cLastName"]');
        const email = this.template.querySelector('[data-id="b2cEmail"]');
        const phone = this.template.querySelector('[data-id="b2cPhone"]');
        const password = this.template.querySelector('[data-id="b2cPassword"]');
        const confirm = this.template.querySelector('[data-id="b2cConfirm"]');

        if (!firstName || !firstName.value || !lastName || !lastName.value || !email || !email.value || !password || !password.value) {
            this.errorMessage = 'Please fill in all required fields.';
            return;
        }
        if (password.value !== confirm.value) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }
        if (password.value.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        registerB2C({
            firstName: firstName.value,
            lastName: lastName.value,
            email: email.value,
            phone: phone ? phone.value : '',
            password: password.value
        })
            .then(result => {
                this.isLoading = false;
                if (result.status === 'success') {
                    this.verificationEmail = result.email;
                    this.verificationMessage = result.message;
                    this.currentStep = 'verify';
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = error.body ? error.body.message : 'An error occurred. Please try again.';
            });
    }

    // ═══ Register B2B ═══
    handleRegisterB2B() {
        const company = this.template.querySelector('[data-id="b2bCompany"]');
        const firstName = this.template.querySelector('[data-id="b2bFirstName"]');
        const lastName = this.template.querySelector('[data-id="b2bLastName"]');
        const email = this.template.querySelector('[data-id="b2bEmail"]');
        const phone = this.template.querySelector('[data-id="b2bPhone"]');
        const industry = this.template.querySelector('[data-id="b2bIndustry"]');
        const password = this.template.querySelector('[data-id="b2bPassword"]');
        const confirm = this.template.querySelector('[data-id="b2bConfirm"]');

        if (!company || !company.value || !firstName || !firstName.value || !lastName || !lastName.value || !email || !email.value || !password || !password.value) {
            this.errorMessage = 'Please fill in all required fields.';
            return;
        }
        if (!industry || !industry.value) {
            this.errorMessage = 'Please select your industry.';
            return;
        }
        if (password.value !== confirm.value) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }
        if (password.value.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        registerB2B({
            companyName: company.value,
            firstName: firstName.value,
            lastName: lastName.value,
            email: email.value,
            phone: phone ? phone.value : '',
            industry: industry.value,
            password: password.value
        })
            .then(result => {
                this.isLoading = false;
                if (result.status === 'success') {
                    this.verificationEmail = result.email;
                    this.verificationMessage = result.message;
                    this.currentStep = 'verify';
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.errorMessage = error.body ? error.body.message : 'An error occurred. Please try again.';
            });
    }

    // ═══ Email Verification ═══
    handleVerificationInput(event) {
        this.verificationCode = event.target.value;
    }

    handleVerifyCode() {
        if (!this.verificationCode || this.verificationCode.length !== 6) {
            this.verificationError = 'Please enter the 6-digit code.';
            return;
        }
        this.isVerifying = true;
        this.verificationError = '';

        verifyEmail({ email: this.verificationEmail, code: this.verificationCode })
            .then(result => {
                this.isVerifying = false;
                if (result.status === 'verified' || result.status === 'already_verified') {
                    this.verificationMessage = result.message;
                    this.verificationError = '';
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        this.currentStep = 'signin';
                        this.verificationCode = '';
                        this.verificationMessage = '';
                    }, 2000);
                }
            })
            .catch(error => {
                this.isVerifying = false;
                this.verificationError = error.body ? error.body.message : 'Verification failed.';
            });
    }

    handleResendCode() {
        this.verificationError = '';
        this.verificationMessage = 'Sending new code...';

        resendVerificationCode({ email: this.verificationEmail })
            .then(() => {
                this.verificationMessage = 'A new code has been sent to ' + this.verificationEmail;
            })
            .catch(error => {
                this.verificationError = error.body ? error.body.message : 'Failed to resend code.';
                this.verificationMessage = '';
            });
    }

    // ═══ Forgot Password ═══
    handleShowForgotPassword() {
        this.currentStep = 'forgot';
        this.forgotMessage = '';
        this.forgotError = '';
        this.forgotEmail = '';
    }

    handleForgotEmailInput(event) {
        this.forgotEmail = event.target.value;
    }

    handleSendResetLink() {
        if (!this.forgotEmail) {
            this.forgotError = 'Please enter your email.';
            return;
        }
        this.isSendingReset = true;
        this.forgotError = '';

        forgotPassword({ email: this.forgotEmail })
            .then(result => {
                this.isSendingReset = false;
                this.forgotMessage = result.message;
            })
            .catch(error => {
                this.isSendingReset = false;
                this.forgotError = error.body ? error.body.message : 'Failed to send reset link.';
            });
    }

    // ═══ Logout ═══
    confirmLogout() { this.currentStep = 'confirmlogout'; }
    cancelLogout() { this.currentStep = 'profile'; }

    handleLogout() {
        this.currentStep = 'loggingout';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            window.location.href = '/secur/logout.jsp?retUrl=/TalFlowExpress/s/';
        }, 2000);
    }

    // ═══ Social Login ═══
    loginWithGoogle() {
        window.location.href = '/TalFlowExpress/services/auth/sso/Google?startURL=/TalFlowExpress/s/';
    }

    loginWithFacebook() {
        window.location.href = '/TalFlowExpress/services/auth/sso/Facebook?startURL=/TalFlowExpress/s/';
    }

    // ═══ Photo Upload ═══
    triggerPhotoUpload() {
        const input = this.template.querySelector('[data-id="photoInput"]');
        if (input) input.click();
    }

    handlePhotoSelect(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (file.size > 2 * 1024 * 1024) { this.errorMessage = 'Image must be less than 2MB.'; return; }
        if (!file.type.startsWith('image/')) { this.errorMessage = 'Please select an image file.'; return; }

        this.tempFileName = file.name;
        this.errorMessage = '';

        const reader = new FileReader();
        reader.onload = () => {
            this.tempPhotoUrl = reader.result;
            this.tempPhotoBase64 = reader.result.split(',')[1];
            this.photoX = 50;
            this.photoY = 50;
            this.photoZoom = 100;
            this.showPhotoEditor = true;
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
    }

    resetPhotoPosition() { this.photoX = 50; this.photoY = 50; this.photoZoom = 100; }
    handleZoom(event) { this.photoZoom = parseInt(event.target.value, 10); }
    cancelPhotoEdit() { this.showPhotoEditor = false; this.tempPhotoUrl = ''; this.tempPhotoBase64 = ''; }

    savePhoto() {
        this.showPhotoEditor = false;
        this.isUploadingPhoto = true;

        uploadProfilePhoto({
            fileName: this.tempFileName,
            base64Data: this.tempPhotoBase64,
            contactId: this.userContactId
        })
            .then(result => {
                this.isUploadingPhoto = false;
                this.userData = { ...this.userData, photoUrl: result };
                this.tempPhotoUrl = '';
                this.tempPhotoBase64 = '';
            })
            .catch(error => {
                this.isUploadingPhoto = false;
                this.errorMessage = error.body ? error.body.message : 'Failed to upload photo.';
            });
    }

    renderedCallback() {
        if (this.showPhotoEditor) {
            const img = this.template.querySelector('[data-id="previewImg"]');
            if (img) {
                img.style.objectPosition = this.photoX + '% ' + this.photoY + '%';
                img.style.transform = 'scale(' + (this.photoZoom / 100) + ')';
            }
        }
        const profileImg = this.template.querySelector('[data-id="profileImg"]');
        if (profileImg) {
            profileImg.style.objectPosition = this.photoX + '% ' + this.photoY + '%';
        }
    }
    connectedCallback() {
        this._profileUpdatedHandler = () => {
            refreshApex(this._wiredUserResult);
        };
        window.addEventListener('profileUpdated', this._profileUpdatedHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('profileUpdated', this._profileUpdatedHandler);
    }
}