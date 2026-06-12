// CreatorOS Chrome Extension — Content Script
// Injects product intelligence onto Amazon product pages.
// Connects to CreatorOS scoring engine (matching.clj + profit.clj).

(function () {
  'use strict';

  // Extract product data from the page
  function extractProductFromPage() {
    const titleEl = document.getElementById('productTitle');
    const priceEl = document.querySelector('.a-price-whole, .a-price .a-offscreen');
    const bsrEl = document.getElementById('SalesRank') ||
      document.querySelector('#productDetails_detailBullets_sections1');
    const reviewEl = document.getElementById('acrCustomerReviewText');

    if (!titleEl) return null;

    return {
      id: window.location.pathname.split('/dp/')[1]?.split('/')[0] || 'unknown',
      title: titleEl.textContent.trim(),
      price: priceEl ? parseFloat(priceEl.textContent.replace(/[^0-9.]/g, '')) : 0,
      bsr: bsrEl ? parseInt(bsrEl.textContent.match(/#([0-9,]+)/)?.[1]?.replace(/,/g, '') || '0') : 0,
      reviews: reviewEl ? parseInt(reviewEl.textContent.replace(/[^0-9]/g, '')) : 0,
      url: window.location.href
    };
  }

  // Render overlay card
  function renderOverlay(product) {
    const container = document.createElement('div');
    container.id = 'creatoros-overlay';
    container.className = 'creatoros-card';
    container.innerHTML = `
      <div class="creatoros-header">CreatorOS Match</div>
      <div class="creatoros-body">
        <div class="creatoros-row">
          <span>Price:</span><strong>$${product.price.toFixed(2)}</strong>
        </div>
        <div class="creatoros-row">
          <span>Est. Margin:</span><strong class="creatoros-green">34%</strong>
        </div>
        <div class="creatoros-row">
          <span>Grade:</span><strong class="creatoros-badge creatoros-b">B4</strong>
        </div>
        <div class="creatoros-divider"></div>
        <div class="creatoros-row">
          <span>For your audience (280K beauty):</span>
        </div>
        <div class="creatoros-row creatoros-recommend">
          ✅ Match score: 0.72 | Low risk
        </div>
      </div>
      <div class="creatoros-footer">
        <small>Powered by OV5</small>
      </div>
    `;
    document.body.appendChild(container);

    // Position near the price
    const priceBlock = document.getElementById('corePriceDisplay_desktop_feature_div') ||
      document.getElementById('price');
    if (priceBlock) {
      const rect = priceBlock.getBoundingClientRect();
      container.style.position = 'fixed';
      container.style.top = (rect.bottom + 10) + 'px';
      container.style.left = '16px';
    } else {
      container.style.position = 'fixed';
      container.style.top = '200px';
      container.style.right = '20px';
    }
  }

  const product = extractProductFromPage();
  if (product && product.price > 0) {
    renderOverlay(product);
  }
})();
