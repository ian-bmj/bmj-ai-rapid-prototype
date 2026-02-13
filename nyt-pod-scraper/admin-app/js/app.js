/**
 * Pod Monitor Admin - Main Application Module
 * Handles SPA routing, navigation state, global event delegation,
 * and view lifecycle management.
 */

import * as api from './api.js';
import * as views from './views.js';

// ============================================================
// STATE
// ============================================================

const state = {
  currentRoute: '',
  currentView: null,
  emailType: 'daily'
};

// ============================================================
// ROUTING
// ============================================================

const routes = [
  { pattern: /^#?$/, handler: () => navigate('#dashboard') },
  { pattern: /^#dashboard$/, handler: renderView('dashboard', views.renderDashboard) },
  { pattern: /^#podcasts$/, handler: renderView('podcasts', views.renderPodcasts) },
  { pattern: /^#podcast\/(.+)$/, handler: (m) => renderView('podcasts', () => views.renderPodcastDetail(m[1]))() },
  { pattern: /^#episodes$/, handler: renderView('episodes', views.renderEpisodes) },
  { pattern: /^#episode\/(.+)$/, handler: (m) => renderView('episodes', () => views.renderEpisodeDetail(m[1]))() },
  { pattern: /^#email$/, handler: renderView('email', views.renderEmailDigest) },
  { pattern: /^#distribution$/, handler: renderView('distribution', views.renderDistributionLists) },
  { pattern: /^#settings$/, handler: renderView('settings', views.renderSettings) }
];

/** Create a view render function that shows loading, then injects the view HTML. */
function renderView(navKey, viewFn) {
  return async () => {
    updateNav(navKey);
    const main = document.getElementById('app-content');
    main.innerHTML = views.renderLoading();
    try {
      const html = await viewFn();
      main.innerHTML = html;
      setupViewListeners(navKey);
    } catch (err) {
      console.error('View render error:', err);
      main.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">&#9888;</div>
          <h4>Something went wrong</h4>
          <p>${escText(err.message)}</p>
          <button class="btn btn-primary" onclick="location.hash='#dashboard'">Back to Dashboard</button>
        </div>
      `;
    }
  };
}

function escText(str) {
  const el = document.createElement('span');
  el.textContent = str || '';
  return el.innerHTML;
}

/** Route the current hash. */
function route() {
  const hash = location.hash || '#dashboard';
  if (hash === state.currentRoute) return;
  state.currentRoute = hash;

  for (const r of routes) {
    const match = hash.match(r.pattern);
    if (match) {
      r.handler(match);
      return;
    }
  }
  // Fallback
  navigate('#dashboard');
}

/** Navigate to a new hash. */
function navigate(hash) {
  location.hash = hash;
}

/** Update the active nav link. */
function updateNav(key) {
  document.querySelectorAll('.app-nav-list a').forEach(a => {
    const navKey = a.getAttribute('data-nav');
    if (navKey === key) {
      a.classList.add('active');
    } else {
      a.classList.remove('active');
    }
  });
}

// ============================================================
// TOAST NOTIFICATIONS
// ============================================================

function showToast(type, title, message) {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const icons = {
    success: '&#10003;',
    error: '&#10007;',
    info: '&#8505;',
    warning: '&#9888;'
  };

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `
    <span class="toast-icon">${icons[type] || icons.info}</span>
    <div class="toast-body">
      <div class="toast-title">${escText(title)}</div>
      <div class="toast-message">${escText(message)}</div>
    </div>
    <button class="toast-dismiss">&times;</button>
  `;

  container.appendChild(toast);

  const dismiss = () => {
    toast.classList.add('toast-leaving');
    setTimeout(() => toast.remove(), 300);
  };

  toast.querySelector('.toast-dismiss').addEventListener('click', dismiss);
  setTimeout(dismiss, 5000);
}

// ============================================================
// EVENT DELEGATION
// ============================================================

function setupGlobalListeners() {
  const main = document.getElementById('app-content');

  // Clickable table rows
  main.addEventListener('click', (e) => {
    const row = e.target.closest('[data-navigate]');
    if (row && !e.target.closest('a, button')) {
      navigate(row.getAttribute('data-navigate'));
    }
  });

  // All data-action buttons
  main.addEventListener('click', async (e) => {
    const actionEl = e.target.closest('[data-action]');
    if (!actionEl) return;

    const action = actionEl.getAttribute('data-action');
    await handleAction(action, actionEl, e);
  });

  // Modal overlay (clicking backdrop to close)
  document.body.addEventListener('click', (e) => {
    if (e.target.classList.contains('modal-overlay')) {
      closeModal();
    }
  });
}

async function handleAction(action, el, e) {
  switch (action) {
    // -- Dashboard --
    case 'seed-demo': {
      el.classList.add('btn-loading');
      try {
        await api.seedDemoData();
        showToast('success', 'Demo Data Seeded', 'Sample podcasts, episodes, and configuration have been loaded.');
        route(); // Refresh current view
      } catch (err) {
        showToast('error', 'Seed Failed', err.message);
      }
      break;
    }

    case 'scrape-all': {
      el.classList.add('btn-loading');
      try {
        const podcasts = await api.fetchPodcasts();
        const active = podcasts.filter(p => p.active);
        for (const pod of active) {
          await api.triggerScrape(pod.id);
        }
        showToast('success', 'Scrape Complete', `Scraped ${active.length} active feeds.`);
        state.currentRoute = ''; // Force re-render
        route();
      } catch (err) {
        showToast('error', 'Scrape Failed', err.message);
      }
      break;
    }

    case 'generate-daily': {
      navigate('#email');
      break;
    }

    // -- Podcasts --
    case 'open-add-podcast': {
      openModal(views.renderAddPodcastModal());
      break;
    }

    case 'close-modal': {
      closeModal();
      break;
    }

    case 'submit-add-podcast': {
      const form = document.getElementById('add-podcast-form');
      if (!form.checkValidity()) {
        form.reportValidity();
        return;
      }
      const data = Object.fromEntries(new FormData(form));
      el.classList.add('btn-loading');
      try {
        await api.addPodcast(data);
        closeModal();
        showToast('success', 'Podcast Added', `"${data.name}" has been added to your monitored feeds.`);
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Add Failed', err.message);
      }
      break;
    }

    case 'toggle-podcast': {
      const id = el.getAttribute('data-id');
      const isActive = el.getAttribute('data-active') === 'true';
      try {
        await api.updatePodcast(id, { active: !isActive });
        showToast('info', 'Podcast Updated', `Podcast ${isActive ? 'paused' : 'activated'}.`);
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Update Failed', err.message);
      }
      break;
    }

    case 'delete-podcast': {
      const id = el.getAttribute('data-id');
      const name = el.getAttribute('data-name');
      if (!confirm(`Are you sure you want to delete "${name}"? This will also remove all its episodes.`)) return;
      try {
        await api.deletePodcast(id);
        showToast('success', 'Podcast Deleted', `"${name}" and its episodes have been removed.`);
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Delete Failed', err.message);
      }
      break;
    }

    case 'scrape-podcast': {
      const id = el.getAttribute('data-id');
      el.classList.add('btn-loading');
      try {
        await api.triggerScrape(id);
        showToast('success', 'Scrape Complete', 'Feed has been scraped for new episodes.');
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Scrape Failed', err.message);
      }
      break;
    }

    // -- Episodes --
    case 'transcribe': {
      const id = el.getAttribute('data-id');
      el.classList.add('btn-loading');
      try {
        await api.triggerTranscribe(id);
        showToast('success', 'Transcription Complete', 'Episode has been transcribed.');
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Transcription Failed', err.message);
      }
      break;
    }

    case 'summarize': {
      const id = el.getAttribute('data-id');
      el.classList.add('btn-loading');
      try {
        await api.triggerSummarize(id);
        showToast('success', 'Summary Generated', 'AI analysis has been generated for this episode.');
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Summarization Failed', err.message);
      }
      break;
    }

    // -- Email --
    case 'refresh-preview': {
      el.classList.add('btn-loading');
      try {
        const preview = state.emailType === 'daily'
          ? await api.previewDailyEmail()
          : await api.previewWeeklyEmail();
        document.getElementById('email-preview-body').innerHTML = preview.html;
        showToast('info', 'Preview Refreshed', 'Email preview has been updated.');
      } catch (err) {
        showToast('error', 'Preview Failed', err.message);
      }
      el.classList.remove('btn-loading');
      break;
    }

    case 'send-email': {
      const type = el.getAttribute('data-type') || state.emailType;
      if (!confirm(`Send the ${type} digest to all subscribers?`)) return;
      el.classList.add('btn-loading');
      try {
        const result = type === 'daily'
          ? await api.sendDailyEmail()
          : await api.sendWeeklyEmail();
        showToast('success', 'Email Sent', result.message);
      } catch (err) {
        showToast('error', 'Send Failed', err.message);
      }
      el.classList.remove('btn-loading');
      break;
    }

    // -- Distribution --
    case 'add-subscriber': {
      const type = el.getAttribute('data-type');
      const input = document.getElementById(`${type}-email-input`);
      const email = input.value.trim();
      if (!email || !email.includes('@')) {
        showToast('warning', 'Invalid Email', 'Please enter a valid email address.');
        return;
      }
      try {
        const lists = await api.fetchDistributionLists();
        if (lists[type].includes(email)) {
          showToast('warning', 'Duplicate', 'This email is already in the list.');
          return;
        }
        lists[type].push(email);
        await api.updateDistributionLists(lists);
        input.value = '';
        showToast('success', 'Subscriber Added', `${email} added to ${type} list.`);
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Add Failed', err.message);
      }
      break;
    }

    case 'remove-subscriber': {
      const type = el.getAttribute('data-type');
      const email = el.getAttribute('data-email');
      try {
        const lists = await api.fetchDistributionLists();
        lists[type] = lists[type].filter(e => e !== email);
        await api.updateDistributionLists(lists);
        showToast('info', 'Subscriber Removed', `${email} removed from ${type} list.`);
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Remove Failed', err.message);
      }
      break;
    }

    // -- Settings --
    case 'save-settings': {
      // Handled by form submit event
      break;
    }

    case 'reset-settings': {
      if (!confirm('Reset all settings to their default values?')) return;
      try {
        await api.seedDemoData();
        showToast('info', 'Settings Reset', 'All settings have been restored to defaults.');
        state.currentRoute = '';
        route();
      } catch (err) {
        showToast('error', 'Reset Failed', err.message);
      }
      break;
    }
  }
}

// ============================================================
// VIEW-SPECIFIC LISTENERS
// ============================================================

function setupViewListeners(navKey) {
  switch (navKey) {
    case 'email':
      setupEmailListeners();
      break;
    case 'episodes':
      setupEpisodesFilterListeners();
      break;
    case 'settings':
      setupSettingsListeners();
      break;
  }
}

function setupEmailListeners() {
  const toggleBtns = document.querySelectorAll('[data-email-type]');
  toggleBtns.forEach(btn => {
    btn.addEventListener('click', async () => {
      const type = btn.getAttribute('data-email-type');
      state.emailType = type;

      // Update toggle button state
      toggleBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      // Update preview
      try {
        const preview = type === 'daily'
          ? await api.previewDailyEmail()
          : await api.previewWeeklyEmail();
        document.getElementById('email-preview-body').innerHTML = preview.html;

        // Update info
        const distLists = await api.fetchDistributionLists();
        const count = distLists[type].length;
        document.getElementById('email-recipient-info').innerHTML =
          `Recipients: <strong>${count}</strong> ${type} subscribers`;
        document.getElementById('email-subject').textContent =
          type === 'daily' ? 'BMJ Pod Monitor - Daily Digest' : 'BMJ Pod Monitor - Weekly Report';

        // Update send button
        const sendBtn = document.querySelector('[data-action="send-email"]');
        if (sendBtn) sendBtn.setAttribute('data-type', type);
      } catch (err) {
        showToast('error', 'Preview Error', err.message);
      }
    });
  });
}

function setupEpisodesFilterListeners() {
  const searchInput = document.querySelector('[data-filter="search"]');
  const podcastSelect = document.querySelector('[data-filter="podcast"]');
  const statusSelect = document.querySelector('[data-filter="status"]');

  function filterRows() {
    const searchVal = (searchInput?.value || '').toLowerCase();
    const podcastVal = podcastSelect?.value || '';
    const statusVal = statusSelect?.value || '';

    const rows = document.querySelectorAll('#episodes-table tbody tr');
    rows.forEach(row => {
      const title = row.getAttribute('data-title') || '';
      const podId = row.getAttribute('data-podcast-id') || '';
      const status = row.getAttribute('data-status') || '';

      const matchSearch = !searchVal || title.includes(searchVal);
      const matchPodcast = !podcastVal || podId === podcastVal;
      const matchStatus = !statusVal || status === statusVal;

      row.style.display = (matchSearch && matchPodcast && matchStatus) ? '' : 'none';
    });
  }

  searchInput?.addEventListener('input', filterRows);
  podcastSelect?.addEventListener('change', filterRows);
  statusSelect?.addEventListener('change', filterRows);
}

function setupSettingsListeners() {
  const form = document.getElementById('settings-form');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(form);
    const data = Object.fromEntries(formData);
    // Convert numeric fields
    data.scrape_interval_hours = parseInt(data.scrape_interval_hours, 10);
    data.max_episodes_per_feed = parseInt(data.max_episodes_per_feed, 10);
    data.smtp_port = parseInt(data.smtp_port, 10);

    const saveBtn = form.querySelector('[data-action="save-settings"]');
    if (saveBtn) saveBtn.classList.add('btn-loading');

    try {
      await api.updateConfig(data);
      showToast('success', 'Settings Saved', 'Your configuration has been updated.');
    } catch (err) {
      showToast('error', 'Save Failed', err.message);
    }

    if (saveBtn) saveBtn.classList.remove('btn-loading');
  });
}

// ============================================================
// MODAL MANAGEMENT
// ============================================================

function openModal(html) {
  // Remove any existing modal
  closeModal();
  const container = document.createElement('div');
  container.id = 'modal-container';
  container.innerHTML = html;
  document.body.appendChild(container);

  // Setup listeners inside modal
  container.addEventListener('click', (e) => {
    const actionEl = e.target.closest('[data-action]');
    if (actionEl) {
      handleAction(actionEl.getAttribute('data-action'), actionEl, e);
    }
  });

  // Trap ESC key
  const escHandler = (e) => {
    if (e.key === 'Escape') {
      closeModal();
      document.removeEventListener('keydown', escHandler);
    }
  };
  document.addEventListener('keydown', escHandler);
}

function closeModal() {
  const container = document.getElementById('modal-container');
  if (container) container.remove();
}

// ============================================================
// INITIALIZATION
// ============================================================

async function init() {
  // Detect backend
  const hasBackend = await api.detectBackend();

  // Show/hide demo badge
  const demoBadge = document.getElementById('demo-badge');
  if (demoBadge) {
    demoBadge.style.display = api.isDemoMode() ? 'inline-block' : 'none';
  }

  if (!hasBackend) {
    console.log('Pod Monitor: Running in demo mode (no backend detected)');
  } else {
    console.log('Pod Monitor: Connected to backend');
  }

  // Setup global event delegation
  setupGlobalListeners();

  // Listen for hash changes
  window.addEventListener('hashchange', route);

  // Initial route
  route();
}

// Start
init();
