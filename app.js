// BMJ AI Rapid Prototype - Hello World
// Simple JavaScript for basic interactivity

document.addEventListener('DOMContentLoaded', function() {
  console.log('Hello World! BMJ AI Rapid Prototype loaded successfully.');

  // Get Started button interaction
  const getStartedBtn = document.querySelector('.hero-section .btn');
  if (getStartedBtn) {
    getStartedBtn.addEventListener('click', function(e) {
      e.preventDefault();
      // Smooth scroll to welcome card
      const welcomeCard = document.querySelector('.welcome-card');
      if (welcomeCard) {
        welcomeCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
      console.log('Get Started button clicked!');
    });
  }

  // Add hover effects to feature cards
  const featureCards = document.querySelectorAll('.card-hover');
  featureCards.forEach(card => {
    card.addEventListener('mouseenter', function() {
      console.log('Feature card hovered:', this.querySelector('.card-title').textContent);
    });
  });

  // Log page load time
  if (window.performance) {
    const loadTime = window.performance.timing.domContentLoadedEventEnd -
                     window.performance.timing.navigationStart;
    console.log(`Page loaded in ${loadTime}ms`);
  }

  // Mobile menu toggle (placeholder for future functionality)
  const headerLogo = document.querySelector('.bmj-header-logo');
  if (headerLogo) {
    console.log('BMJ Header initialized');
  }
});

// Window load event
window.addEventListener('load', function() {
  console.log('All resources loaded. Page is fully interactive.');
});
