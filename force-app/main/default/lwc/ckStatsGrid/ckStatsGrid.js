import { LightningElement, track } from 'lwc';

export default class CkStatsCounter extends LightningElement {
    @track stats = [
        { id: 's1', target: 500, suffix: '+', label: 'Products', display: '0+', current: 0 },
        { id: 's2', target: 12, suffix: 'K+', label: 'Happy Customers', display: '0K+', current: 0 },
        { id: 's3', target: 24, suffix: 'h', label: 'Fast Shipping', display: '0h', current: 0 },
        { id: 's4', target: 4.9, suffix: '★', label: 'Average Rating', display: '0★', current: 0, decimal: true }
    ];

    _observed = false;
    _animated = false;

    renderedCallback() {
        if (this._observed) return;
        this._observed = true;

        const target = this.template.querySelector('[data-id="stats"]');
        if (target) {
            const observer = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting && !this._animated) {
                        this._animated = true;
                        this.animateAll();
                        observer.disconnect();
                    }
                });
            }, { threshold: 0.3 });

            observer.observe(target);
        }
    }

    animateAll() {
        this.stats.forEach((stat, index) => {
            this.animateStat(index);
        });
    }

    animateStat(index) {
        const stat = this.stats[index];
        const duration = 2000;
        const steps = 60;
        const stepTime = duration / steps;
        const increment = stat.target / steps;
        let current = 0;
        let step = 0;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        const timer = setInterval(() => {
            step++;
            // Easing — ralentit vers la fin
            const progress = step / steps;
            const eased = 1 - Math.pow(1 - progress, 3);
            current = stat.target * eased;

            if (step >= steps) {
                current = stat.target;
                clearInterval(timer);
            }

            // Mise à jour
            const updated = [...this.stats];
            if (stat.decimal) {
                updated[index] = { ...stat, display: current.toFixed(1) + stat.suffix, current: current };
            } else {
                updated[index] = { ...stat, display: Math.floor(current) + stat.suffix, current: current };
            }
            this.stats = updated;
        }, stepTime);
    }
}