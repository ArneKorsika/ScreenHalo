const measurementId = 'G-7W3NRFBXHQ';
const consentKey = 'screenhalo.analyticsConsent';
const consentBanner = document.getElementById('analytics-consent');
const settingsButton = document.getElementById('analytics-settings');
let consent = readConsent();
let analyticsStarted = false;

window.dataLayer = window.dataLayer || [];
window.gtag = function () {
  window.dataLayer.push(arguments);
};
window[`ga-disable-${measurementId}`] = true;
window.gtag('consent', 'default', {
  analytics_storage: 'denied',
  ad_storage: 'denied',
  ad_user_data: 'denied',
  ad_personalization: 'denied'
});

function readConsent() {
  try {
    const saved = JSON.parse(localStorage.getItem(consentKey));
    if (saved?.expires > Date.now() && ['granted', 'denied'].includes(saved.value)) {
      return saved.value;
    }
  } catch {}
  return null;
}

function startAnalytics() {
  window[`ga-disable-${measurementId}`] = false;
  window.gtag('consent', 'update', { analytics_storage: 'granted' });
  if (analyticsStarted) return;
  analyticsStarted = true;

  window.gtag('js', new Date());
  window.gtag('config', measurementId, {
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
    cookie_expires: 60 * 60 * 24 * 180,
    page_location: window.location.origin + window.location.pathname,
    page_referrer: document.referrer ? new URL(document.referrer).origin : ''
  });

  if (!['screenhalo.si', 'www.screenhalo.si'].includes(window.location.hostname)) return;
  const script = document.createElement('script');
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
  document.head.append(script);
}

function clearAnalyticsCookies() {
  const domains = [''];
  const parts = window.location.hostname.split('.');
  for (let index = 0; index < parts.length - 1; index++) {
    const domain = parts.slice(index).join('.');
    domains.push(domain, `.${domain}`);
  }

  for (const cookie of document.cookie.split(';')) {
    const name = cookie.trim().split('=')[0];
    if (name !== '_ga' && !name.startsWith('_ga_')) continue;
    for (const domain of domains) {
      const domainAttribute = domain ? `; Domain=${domain}` : '';
      document.cookie = `${name}=; Max-Age=0; Path=/${domainAttribute}`;
    }
  }
}

function saveConsent(value) {
  consent = value;
  try {
    localStorage.setItem(consentKey, JSON.stringify({
      value,
      expires: Date.now() + 180 * 24 * 60 * 60 * 1000
    }));
  } catch {}

  consentBanner.hidden = true;
  settingsButton.setAttribute('aria-expanded', 'false');

  if (value === 'granted') {
    startAnalytics();
  } else {
    window[`ga-disable-${measurementId}`] = true;
    clearAnalyticsCookies();
    if (analyticsStarted) window.location.reload();
  }
}

function trackLink(event) {
  if (event.button !== 0 && event.button !== 1) return;
  if (consent !== 'granted') return;
  const link = event.target.closest('a[href]');
  if (!link) return;
  const url = new URL(link.href);
  const linkLocation = link.closest('section[id]')?.id || (link.closest('footer') ? 'footer' : 'header');
  const parameters = {
    send_to: measurementId,
    link_url: url.origin + url.pathname,
    link_location: linkLocation
  };
  let eventName;

  if (link.classList.contains('zoom')) {
    eventName = 'screenshot_open';
    parameters.file_name = url.pathname.split('/').pop();
  } else if (url.hostname === 'github.com') {
    const path = url.pathname.replace(/\/$/, '');
    if (/^\/ArneKorsika\/ScreenHalo\/releases\/(?:latest\/download|download)\//.test(path)) {
      eventName = 'download_click';
    } else if (path === '/ArneKorsika/ScreenHalo') {
      eventName = 'source_click';
    } else if (path === '/ArneKorsika/ScreenHalo/issues') {
      eventName = 'issue_click';
    }
  }

  if (eventName) window.gtag('event', eventName, parameters);
}

settingsButton.addEventListener('click', () => {
  consentBanner.hidden = false;
  settingsButton.setAttribute('aria-expanded', 'true');
  document.getElementById('analytics-reject').focus();
});
document.getElementById('analytics-accept').addEventListener('click', () => saveConsent('granted'));
document.getElementById('analytics-reject').addEventListener('click', () => saveConsent('denied'));
document.addEventListener('click', trackLink);
document.addEventListener('auxclick', trackLink);
window.addEventListener('storage', (event) => {
  if (event.key === consentKey) {
    window[`ga-disable-${measurementId}`] = true;
    window.location.reload();
  }
});

if (consent === 'granted') {
  startAnalytics();
} else if (consent === null) {
  consentBanner.hidden = false;
} else {
  clearAnalyticsCookies();
}
