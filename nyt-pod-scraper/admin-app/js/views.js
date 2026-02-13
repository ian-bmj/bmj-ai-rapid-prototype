/**
 * Pod Monitor Admin - View Rendering Module
 * Each function returns an HTML string for the corresponding view.
 */

import * as api from './api.js';

// ============================================================
// HELPERS
// ============================================================

/** Format an ISO date string for display. */
function fmtDate(iso) {
  if (!iso) return '--';
  const d = new Date(iso);
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

function fmtDateTime(iso) {
  if (!iso) return '--';
  const d = new Date(iso);
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) +
    ' ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

function timeAgo(iso) {
  if (!iso) return 'Never';
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

/** Return a CSS class suffix for the category. */
function catClass(category) {
  const map = {
    'health-policy': 'cat-health-policy',
    'medical-research': 'cat-medical-research',
    'public-health': 'cat-public-health',
    'clinical': 'cat-clinical'
  };
  return map[category] || 'cat-default';
}

/** Pretty-print a category slug. */
function catLabel(category) {
  const map = {
    'health-policy': 'Health Policy',
    'medical-research': 'Medical Research',
    'public-health': 'Public Health',
    'clinical': 'Clinical'
  };
  return map[category] || category || 'General';
}

/** Status badge HTML. */
function statusBadge(status) {
  const labels = {
    'new': 'New',
    'transcribed': 'Transcribed',
    'summarized': 'Summarized',
    'processing': 'Processing',
    'error': 'Error'
  };
  return `<span class="status-badge status-${status}">${labels[status] || status}</span>`;
}

/** Escape HTML for safe insertion. */
function esc(str) {
  if (!str) return '';
  const el = document.createElement('span');
  el.textContent = str;
  return el.innerHTML;
}

// ============================================================
// DASHBOARD VIEW
// ============================================================

export async function renderDashboard() {
  const podcasts = await api.fetchPodcasts();
  const episodes = await api.fetchEpisodes();

  const totalPodcasts = podcasts.length;
  const activePodcasts = podcasts.filter(p => p.active).length;

  const oneWeekAgo = new Date();
  oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
  const episodesThisWeek = episodes.filter(e => new Date(e.date) >= oneWeekAgo).length;

  const pendingTranscriptions = episodes.filter(e => e.status === 'new').length;
  const pendingSummaries = episodes.filter(e => e.status === 'transcribed').length;

  const distLists = await api.fetchDistributionLists();
  const totalSubscribers = new Set([...distLists.daily, ...distLists.weekly]).size;

  const recentEpisodes = episodes.slice(0, 8);

  return `
    <div class="page-header">
      <h2>Dashboard</h2>
      <div class="page-header-actions">
        <button class="btn btn-sm btn-outline-primary" data-action="seed-demo">Seed Demo Data</button>
        <button class="btn btn-sm btn-outline-secondary" data-action="scrape-all">Scrape All Feeds</button>
        <button class="btn btn-sm btn-primary" data-action="generate-daily">Generate Daily Digest</button>
      </div>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-card-header">
          <span class="stat-card-label">Total Podcasts</span>
          <span class="stat-card-icon blue">&#9835;</span>
        </div>
        <div class="stat-card-value">${totalPodcasts}</div>
        <div class="stat-card-change">${activePodcasts} active</div>
      </div>

      <div class="stat-card">
        <div class="stat-card-header">
          <span class="stat-card-label">Episodes This Week</span>
          <span class="stat-card-icon green">&#9654;</span>
        </div>
        <div class="stat-card-value">${episodesThisWeek}</div>
        <div class="stat-card-change">${episodes.length} total</div>
      </div>

      <div class="stat-card">
        <div class="stat-card-header">
          <span class="stat-card-label">Pending Processing</span>
          <span class="stat-card-icon violet">&#8987;</span>
        </div>
        <div class="stat-card-value">${pendingTranscriptions + pendingSummaries}</div>
        <div class="stat-card-change">${pendingTranscriptions} transcriptions, ${pendingSummaries} summaries</div>
      </div>

      <div class="stat-card">
        <div class="stat-card-header">
          <span class="stat-card-label">Distribution</span>
          <span class="stat-card-icon teal">&#9993;</span>
        </div>
        <div class="stat-card-value">${totalSubscribers}</div>
        <div class="stat-card-change">${distLists.daily.length} daily, ${distLists.weekly.length} weekly</div>
      </div>
    </div>

    <div class="recent-section">
      <div class="recent-section-header">
        <h4>Recent Episodes</h4>
        <a href="#episodes" class="btn btn-sm btn-link">View all</a>
      </div>
      <table class="data-table">
        <thead>
          <tr>
            <th>Episode</th>
            <th>Podcast</th>
            <th>Date</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${recentEpisodes.map(ep => `
            <tr class="clickable-row" data-navigate="#episode/${ep.id}">
              <td><strong>${esc(ep.title)}</strong></td>
              <td><span class="category-badge ${catClass(findPodcastCategory(podcasts, ep.podcast_id))}">${esc(ep.podcast_name)}</span></td>
              <td class="nowrap">${fmtDate(ep.date)}</td>
              <td>${statusBadge(ep.status)}</td>
              <td class="text-right">
                <a href="#episode/${ep.id}" class="btn btn-sm btn-link">View</a>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function findPodcastCategory(podcasts, podcastId) {
  const pod = podcasts.find(p => p.id === podcastId);
  return pod ? pod.category : 'default';
}

// ============================================================
// PODCASTS VIEW
// ============================================================

export async function renderPodcasts() {
  const podcasts = await api.fetchPodcasts();

  const podcastCards = podcasts.map(pod => `
    <div class="podcast-card" data-podcast-id="${pod.id}">
      <div class="podcast-card-header">
        <div class="podcast-card-icon ${catClass(pod.category)}">${esc(pod.name.charAt(0))}</div>
        <div class="podcast-card-info">
          <div class="podcast-card-name">
            <a href="#podcast/${pod.id}">${esc(pod.name)}</a>
          </div>
          <span class="category-badge ${catClass(pod.category)}">${catLabel(pod.category)}</span>
        </div>
      </div>
      <div class="podcast-card-body">
        <p class="podcast-card-desc">${esc(pod.description)}</p>
        <div class="podcast-card-meta">
          <span class="podcast-card-meta-item">${pod.episode_count} episodes</span>
          <span class="podcast-card-meta-item">Updated ${timeAgo(pod.last_scraped)}</span>
        </div>
      </div>
      <div class="podcast-card-footer">
        <span class="status-badge ${pod.active ? 'status-active' : 'status-inactive'}">${pod.active ? 'Active' : 'Inactive'}</span>
        <div class="podcast-card-actions">
          <button class="btn btn-sm btn-outline-primary" data-action="toggle-podcast" data-id="${pod.id}" data-active="${pod.active}" title="${pod.active ? 'Deactivate' : 'Activate'}">
            ${pod.active ? 'Pause' : 'Resume'}
          </button>
          <button class="btn btn-sm btn-outline-danger" data-action="delete-podcast" data-id="${pod.id}" data-name="${esc(pod.name)}" title="Delete">Del</button>
        </div>
      </div>
    </div>
  `).join('');

  return `
    <div class="page-header">
      <h2>Podcasts</h2>
      <div class="page-header-actions">
        <button class="btn btn-primary" data-action="open-add-podcast">+ Add Podcast</button>
      </div>
    </div>
    <div class="podcast-grid">
      ${podcastCards || '<div class="empty-state"><div class="empty-state-icon">&#9835;</div><h4>No podcasts yet</h4><p>Add your first podcast feed to start monitoring.</p></div>'}
    </div>
  `;
}

// ============================================================
// PODCAST DETAIL VIEW
// ============================================================

export async function renderPodcastDetail(podcastId) {
  const podcasts = await api.fetchPodcasts();
  const pod = podcasts.find(p => p.id === podcastId);
  if (!pod) {
    return `<div class="empty-state"><h4>Podcast not found</h4><p>The requested podcast could not be found.</p><a href="#podcasts" class="btn btn-primary">Back to Podcasts</a></div>`;
  }

  const episodes = await api.fetchEpisodes(podcastId);

  return `
    <nav class="breadcrumb">
      <a href="#podcasts">Podcasts</a>
      <span class="breadcrumb-separator">/</span>
      <span>${esc(pod.name)}</span>
    </nav>

    <div class="detail-header">
      <div class="detail-header-icon ${catClass(pod.category)}">${esc(pod.name.charAt(0))}</div>
      <div class="detail-header-content">
        <h2>${esc(pod.name)}</h2>
        <p>${esc(pod.description)}</p>
        <div class="detail-meta">
          <span class="detail-meta-item"><strong>Feed:</strong> ${esc(pod.feed_url)}</span>
          <span class="detail-meta-item"><strong>Category:</strong> <span class="category-badge ${catClass(pod.category)}">${catLabel(pod.category)}</span></span>
          <span class="detail-meta-item"><strong>Last scraped:</strong> ${fmtDateTime(pod.last_scraped)}</span>
          <span class="detail-meta-item"><strong>Status:</strong> <span class="status-badge ${pod.active ? 'status-active' : 'status-inactive'}">${pod.active ? 'Active' : 'Inactive'}</span></span>
        </div>
      </div>
      <div class="detail-header-actions">
        <button class="btn btn-sm btn-primary" data-action="scrape-podcast" data-id="${pod.id}">Scrape Now</button>
        <button class="btn btn-sm btn-outline-primary" data-action="toggle-podcast" data-id="${pod.id}" data-active="${pod.active}">${pod.active ? 'Pause' : 'Resume'}</button>
      </div>
    </div>

    <div class="recent-section">
      <div class="recent-section-header">
        <h4>Episodes (${episodes.length})</h4>
      </div>
      ${episodes.length > 0 ? `
      <table class="data-table">
        <thead>
          <tr>
            <th>Title</th>
            <th>Date</th>
            <th>Duration</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${episodes.map(ep => `
            <tr class="clickable-row" data-navigate="#episode/${ep.id}">
              <td><strong>${esc(ep.title)}</strong></td>
              <td class="nowrap">${fmtDate(ep.date)}</td>
              <td>${ep.duration || '--'}</td>
              <td>${statusBadge(ep.status)}</td>
              <td class="text-right">
                <a href="#episode/${ep.id}" class="btn btn-sm btn-link">View</a>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>` : `
      <div class="empty-state">
        <div class="empty-state-icon">&#9654;</div>
        <h4>No episodes yet</h4>
        <p>Try scraping the feed to discover episodes.</p>
      </div>`}
    </div>
  `;
}

// ============================================================
// EPISODES VIEW
// ============================================================

export async function renderEpisodes() {
  const podcasts = await api.fetchPodcasts();
  const episodes = await api.fetchEpisodes();

  const podcastOptions = podcasts.map(p => `<option value="${p.id}">${esc(p.name)}</option>`).join('');

  return `
    <div class="page-header">
      <h2>Episodes</h2>
    </div>

    <div class="filter-bar">
      <div class="filter-search">
        <span class="filter-search-icon">&#128269;</span>
        <input type="text" class="form-input" placeholder="Search episodes..." data-filter="search">
      </div>
      <select class="form-select" data-filter="podcast">
        <option value="">All Podcasts</option>
        ${podcastOptions}
      </select>
      <select class="form-select" data-filter="status">
        <option value="">All Statuses</option>
        <option value="new">New</option>
        <option value="transcribed">Transcribed</option>
        <option value="summarized">Summarized</option>
      </select>
    </div>

    <div class="recent-section">
      <table class="data-table" id="episodes-table">
        <thead>
          <tr>
            <th data-sort="title" class="cursor-pointer">Title</th>
            <th data-sort="podcast">Podcast</th>
            <th data-sort="date" class="cursor-pointer">Date</th>
            <th>Duration</th>
            <th data-sort="status">Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${episodes.map(ep => `
            <tr class="clickable-row" data-navigate="#episode/${ep.id}" data-podcast-id="${ep.podcast_id}" data-status="${ep.status}" data-title="${esc(ep.title).toLowerCase()}" data-date="${ep.date}">
              <td><strong>${esc(ep.title)}</strong></td>
              <td><span class="category-badge ${catClass(findPodcastCategory(podcasts, ep.podcast_id))}">${esc(ep.podcast_name)}</span></td>
              <td class="nowrap">${fmtDate(ep.date)}</td>
              <td>${ep.duration || '--'}</td>
              <td>${statusBadge(ep.status)}</td>
              <td class="text-right">
                <a href="#episode/${ep.id}" class="btn btn-sm btn-link">View</a>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

// ============================================================
// EPISODE DETAIL VIEW
// ============================================================

export async function renderEpisodeDetail(episodeId) {
  const episode = await api.fetchEpisode(episodeId);
  const podcasts = await api.fetchPodcasts();
  const podcast = podcasts.find(p => p.id === episode.podcast_id);

  const hasTranscript = episode.transcript != null;
  const hasSummary = episode.summary != null;

  const transcriptContent = hasTranscript
    ? `<div class="transcript-text">${esc(episode.transcript)}</div>`
    : `<div class="empty-state"><div class="empty-state-icon">&#128196;</div><h4>No transcript yet</h4><p>Transcribe this episode to view the text.</p></div>`;

  const summaryContent = hasSummary ? `
    <div class="summary-section">
      <h5>Summary</h5>
      <p>${esc(episode.summary)}</p>
    </div>
    ${episode.gist ? `
    <div class="summary-section">
      <h5>Gist</h5>
      <p><em>${esc(episode.gist)}</em></p>
    </div>` : ''}
    ${episode.themes && episode.themes.length > 0 ? `
    <div class="summary-section">
      <h5>Themes</h5>
      <div class="theme-tags">
        ${episode.themes.map(t => `<span class="theme-tag">${esc(t)}</span>`).join('')}
      </div>
    </div>` : ''}
    ${episode.key_quotes && episode.key_quotes.length > 0 ? `
    <div class="summary-section">
      <h5>Key Quotes</h5>
      ${episode.key_quotes.map(q => `
        <div class="key-quote">
          <p>"${esc(q.text)}"</p>
          ${q.speaker ? `<cite>${esc(q.speaker)}</cite>` : ''}
        </div>
      `).join('')}
    </div>` : ''}
  ` : `<div class="empty-state"><div class="empty-state-icon">&#128221;</div><h4>No summary yet</h4><p>${hasTranscript ? 'Run the summarizer to generate an AI analysis.' : 'Transcribe the episode first, then generate a summary.'}</p></div>`;

  const actionButtons = [];
  if (episode.status === 'new') {
    actionButtons.push(`<button class="btn btn-sm btn-primary" data-action="transcribe" data-id="${episode.id}">Transcribe</button>`);
  }
  if (episode.status === 'transcribed') {
    actionButtons.push(`<button class="btn btn-sm btn-primary" data-action="summarize" data-id="${episode.id}">Summarize</button>`);
  }
  if (podcast) {
    actionButtons.push(`<a href="#podcast/${podcast.id}" class="btn btn-sm btn-outline-secondary">View in Podcast</a>`);
  }

  return `
    <nav class="breadcrumb">
      <a href="#episodes">Episodes</a>
      <span class="breadcrumb-separator">/</span>
      ${podcast ? `<a href="#podcast/${podcast.id}">${esc(podcast.name)}</a><span class="breadcrumb-separator">/</span>` : ''}
      <span>${esc(episode.title)}</span>
    </nav>

    <div class="episode-info-bar">
      <div>
        <h3>${esc(episode.title)}</h3>
        <div class="episode-info-details">
          <span>${esc(episode.podcast_name)}</span>
          <span>${fmtDate(episode.date)}</span>
          <span>${episode.duration || ''}</span>
          ${statusBadge(episode.status)}
        </div>
      </div>
      <div class="d-flex gap-sm">
        ${actionButtons.join('')}
      </div>
    </div>

    <div class="audio-player-placeholder">
      <div class="audio-player-icon">&#9654;</div>
      <div class="audio-player-info">
        <p><strong>Audio Player</strong></p>
        <p>Audio playback would be available here in production. Duration: ${episode.duration || 'Unknown'}</p>
      </div>
    </div>

    <div class="episode-layout">
      <div class="episode-panel">
        <div class="episode-panel-header">
          <h4>Transcript</h4>
          ${!hasTranscript && episode.status === 'new' ? `<button class="btn btn-sm btn-primary" data-action="transcribe" data-id="${episode.id}">Transcribe</button>` : ''}
        </div>
        <div class="episode-panel-body">
          ${transcriptContent}
        </div>
      </div>

      <div class="episode-panel">
        <div class="episode-panel-header">
          <h4>AI Analysis</h4>
          ${hasTranscript && !hasSummary ? `<button class="btn btn-sm btn-primary" data-action="summarize" data-id="${episode.id}">Summarize</button>` : ''}
        </div>
        <div class="episode-panel-body">
          ${summaryContent}
        </div>
      </div>
    </div>
  `;
}

// ============================================================
// EMAIL DIGEST VIEW
// ============================================================

export async function renderEmailDigest() {
  const distLists = await api.fetchDistributionLists();
  const dailyPreview = await api.previewDailyEmail();

  return `
    <div class="page-header">
      <h2>Email Digest</h2>
    </div>

    <div class="email-controls">
      <div class="email-toggle">
        <button class="email-toggle-btn active" data-email-type="daily">Daily Digest</button>
        <button class="email-toggle-btn" data-email-type="weekly">Weekly Report</button>
      </div>
      <div class="email-info">
        <span id="email-recipient-info">Recipients: <strong>${distLists.daily.length}</strong> daily subscribers</span>
        <button class="btn btn-sm btn-outline-primary" data-action="refresh-preview">Refresh Preview</button>
        <button class="btn btn-sm btn-success" data-action="send-email" data-type="daily">Send Digest</button>
      </div>
    </div>

    <div class="email-preview-container">
      <div class="email-preview-toolbar">
        <span class="email-preview-toolbar-info">
          <strong>From:</strong> Pod Monitor &lt;podmonitor@bmj.com&gt; &nbsp; | &nbsp;
          <strong>Subject:</strong> <span id="email-subject">BMJ Pod Monitor - Daily Digest</span>
        </span>
      </div>
      <div class="email-preview-frame">
        <div class="email-preview-content" id="email-preview-body">
          ${dailyPreview.html}
        </div>
      </div>
    </div>
  `;
}

// ============================================================
// DISTRIBUTION LISTS VIEW
// ============================================================

export async function renderDistributionLists() {
  const lists = await api.fetchDistributionLists();

  function renderList(type, emails) {
    return emails.map(email => `
      <li class="subscriber-item">
        <span class="subscriber-email">${esc(email)}</span>
        <button class="subscriber-remove" data-action="remove-subscriber" data-type="${type}" data-email="${esc(email)}" title="Remove">&times;</button>
      </li>
    `).join('');
  }

  return `
    <div class="page-header">
      <h2>Distribution Lists</h2>
    </div>

    <div class="dist-grid">
      <div class="dist-panel">
        <div class="dist-panel-header">
          <h4>Daily Subscribers <span class="badge badge-primary">${lists.daily.length}</span></h4>
        </div>
        <div class="dist-panel-body">
          <div class="dist-add-form">
            <input type="email" class="form-input" placeholder="Add email address..." id="daily-email-input">
            <button class="btn btn-sm btn-primary" data-action="add-subscriber" data-type="daily">Add</button>
          </div>
          <ul class="subscriber-list" id="daily-subscriber-list">
            ${renderList('daily', lists.daily)}
          </ul>
        </div>
      </div>

      <div class="dist-panel">
        <div class="dist-panel-header">
          <h4>Weekly Subscribers <span class="badge badge-info">${lists.weekly.length}</span></h4>
        </div>
        <div class="dist-panel-body">
          <div class="dist-add-form">
            <input type="email" class="form-input" placeholder="Add email address..." id="weekly-email-input">
            <button class="btn btn-sm btn-primary" data-action="add-subscriber" data-type="weekly">Add</button>
          </div>
          <ul class="subscriber-list" id="weekly-subscriber-list">
            ${renderList('weekly', lists.weekly)}
          </ul>
        </div>
      </div>
    </div>
  `;
}

// ============================================================
// SETTINGS VIEW
// ============================================================

export async function renderSettings() {
  const config = await api.fetchConfig();

  return `
    <div class="page-header">
      <h2>Settings</h2>
    </div>

    <form id="settings-form">
    <div class="settings-grid">
      <div class="settings-section">
        <div class="settings-section-header">
          <h4>LLM Configuration</h4>
        </div>
        <div class="settings-section-body">
          <div class="form-group">
            <label class="form-label" for="llm-provider">LLM Provider</label>
            <select class="form-select" id="llm-provider" name="llm_provider">
              <option value="openai" ${config.llm_provider === 'openai' ? 'selected' : ''}>OpenAI</option>
              <option value="anthropic" ${config.llm_provider === 'anthropic' ? 'selected' : ''}>Anthropic</option>
              <option value="google" ${config.llm_provider === 'google' ? 'selected' : ''}>Google (Gemini)</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label" for="api-key">API Key</label>
            <input type="password" class="form-input" id="api-key" name="api_key" value="${esc(config.api_key)}" placeholder="Enter API key...">
            <span class="form-hint">Your API key is stored securely and never displayed in full.</span>
          </div>
          <div class="form-group">
            <label class="form-label" for="model">Model</label>
            <select class="form-select" id="model" name="model">
              <optgroup label="Anthropic">
                <option value="claude-sonnet-4-20250514" ${config.model === 'claude-sonnet-4-20250514' ? 'selected' : ''}>Claude Sonnet 4</option>
                <option value="claude-opus-4-20250514" ${config.model === 'claude-opus-4-20250514' ? 'selected' : ''}>Claude Opus 4</option>
              </optgroup>
              <optgroup label="OpenAI">
                <option value="gpt-4o" ${config.model === 'gpt-4o' ? 'selected' : ''}>GPT-4o</option>
                <option value="gpt-4o-mini" ${config.model === 'gpt-4o-mini' ? 'selected' : ''}>GPT-4o Mini</option>
              </optgroup>
              <optgroup label="Google">
                <option value="gemini-2.0-flash" ${config.model === 'gemini-2.0-flash' ? 'selected' : ''}>Gemini 2.0 Flash</option>
                <option value="gemini-2.5-pro" ${config.model === 'gemini-2.5-pro' ? 'selected' : ''}>Gemini 2.5 Pro</option>
              </optgroup>
            </select>
          </div>
        </div>
      </div>

      <div class="settings-section">
        <div class="settings-section-header">
          <h4>Scraper Settings</h4>
        </div>
        <div class="settings-section-body">
          <div class="form-group">
            <label class="form-label" for="scrape-interval">Check Interval (hours)</label>
            <input type="number" class="form-input" id="scrape-interval" name="scrape_interval_hours" value="${config.scrape_interval_hours}" min="1" max="72">
            <span class="form-hint">How often to check feeds for new episodes.</span>
          </div>
          <div class="form-group">
            <label class="form-label" for="max-episodes">Max Episodes per Feed</label>
            <input type="number" class="form-input" id="max-episodes" name="max_episodes_per_feed" value="${config.max_episodes_per_feed}" min="1" max="100">
            <span class="form-hint">Maximum number of episodes to process per feed per scrape.</span>
          </div>
        </div>
      </div>

      <div class="settings-section" style="grid-column: 1 / -1;">
        <div class="settings-section-header">
          <h4>SMTP / Email Settings</h4>
        </div>
        <div class="settings-section-body">
          <div class="settings-grid" style="margin:0;">
            <div>
              <div class="form-group">
                <label class="form-label" for="smtp-host">SMTP Host</label>
                <input type="text" class="form-input" id="smtp-host" name="smtp_host" value="${esc(config.smtp_host)}">
              </div>
              <div class="form-group">
                <label class="form-label" for="smtp-port">SMTP Port</label>
                <input type="number" class="form-input" id="smtp-port" name="smtp_port" value="${config.smtp_port}">
              </div>
            </div>
            <div>
              <div class="form-group">
                <label class="form-label" for="smtp-user">SMTP Username</label>
                <input type="text" class="form-input" id="smtp-user" name="smtp_user" value="${esc(config.smtp_user)}">
              </div>
              <div class="form-group">
                <label class="form-label" for="smtp-password">SMTP Password</label>
                <input type="password" class="form-input" id="smtp-password" name="smtp_password" value="${esc(config.smtp_password)}" placeholder="Enter SMTP password...">
              </div>
            </div>
          </div>
          <div class="form-group mt-4">
            <label class="form-label" for="from-email">From Email</label>
            <input type="text" class="form-input" id="from-email" name="from_email" value="${esc(config.from_email)}" style="max-width:480px;">
          </div>
        </div>
      </div>
    </div>

    <div class="mt-5 d-flex justify-end gap-sm">
      <button type="button" class="btn btn-secondary" data-action="reset-settings">Reset to Defaults</button>
      <button type="submit" class="btn btn-primary" data-action="save-settings">Save Settings</button>
    </div>
    </form>
  `;
}

// ============================================================
// ADD PODCAST MODAL
// ============================================================

export function renderAddPodcastModal() {
  return `
    <div class="modal-overlay" data-action="close-modal">
      <div class="modal" onclick="event.stopPropagation()">
        <div class="modal-header">
          <h3>Add Podcast</h3>
          <button class="modal-close" data-action="close-modal">&times;</button>
        </div>
        <div class="modal-body">
          <form id="add-podcast-form">
            <div class="form-group">
              <label class="form-label" for="podcast-name">Podcast Name</label>
              <input type="text" class="form-input" id="podcast-name" name="name" required placeholder="e.g., The Health Policy Pod">
            </div>
            <div class="form-group">
              <label class="form-label" for="podcast-feed">RSS Feed URL</label>
              <input type="url" class="form-input" id="podcast-feed" name="feed_url" required placeholder="https://feeds.example.com/podcast/rss">
            </div>
            <div class="form-group">
              <label class="form-label" for="podcast-category">Category</label>
              <select class="form-select" id="podcast-category" name="category">
                <option value="health-policy">Health Policy</option>
                <option value="medical-research">Medical Research</option>
                <option value="public-health">Public Health</option>
                <option value="clinical">Clinical</option>
              </select>
            </div>
            <div class="form-group">
              <label class="form-label" for="podcast-desc">Description</label>
              <textarea class="form-textarea" id="podcast-desc" name="description" rows="3" placeholder="Brief description of the podcast..."></textarea>
            </div>
          </form>
        </div>
        <div class="modal-footer">
          <button class="btn btn-secondary" data-action="close-modal">Cancel</button>
          <button class="btn btn-primary" data-action="submit-add-podcast">Add Podcast</button>
        </div>
      </div>
    </div>
  `;
}

// ============================================================
// LOADING VIEW
// ============================================================

export function renderLoading(message = 'Loading...') {
  return `
    <div class="loading-spinner">
      <div class="spinner"></div>
      <p>${esc(message)}</p>
    </div>
  `;
}
