# PWA (Progressive Web App) Guide

LogYourBody is configured as a Progressive Web App, providing an app-like experience with offline capabilities, installation, and push notifications.

## Current PWA Features

### ✅ Implemented

- **Service Worker**: Handles offline caching and updates
- **Web App Manifest**: Configures app appearance and behavior
- **Install Prompt**: Shows after 30 seconds on compatible devices
- **Offline Support**: Shows offline page when network is unavailable
- **Update Notifications**: Alerts users when new version is available
- **App Icons**: Multiple sizes for different devices
- **Shortcuts**: Quick actions from home screen icon

### 🔧 Configuration Files

1. **Service Worker** (`/public/sw.js`)
   - Caches essential pages and assets
   - Provides offline fallback
   - Handles push notifications (structure ready)

2. **Web Manifest** (`/public/site.webmanifest`)
   - App name and description
   - Theme colors matching dark theme
   - Icon configurations
   - Display mode: standalone
   - Shortcuts to Log Weight and Dashboard

3. **PWA Provider** (`/src/components/PWAProvider.tsx`)
   - Registers service worker
   - Handles install prompts
   - Shows update notifications

4. **Offline Page** (`/public/offline.html`)
   - Styled to match app theme
   - Shows when offline and page not cached

## Testing PWA Features

### Development Testing

1. Start the app with `pnpm dev`
2. Visit http://localhost:3000
3. Use Chrome DevTools to inspect service worker status, the install prompt, and notifications

### Chrome DevTools Testing

1. Open Chrome DevTools (F12)
2. Go to **Application** tab
3. Check:
   - **Service Workers**: Should show sw.js as activated
   - **Manifest**: Should display app info
   - **Storage**: View cached files

### Lighthouse PWA Audit

1. Open Chrome DevTools
2. Go to **Lighthouse** tab
3. Select "Progressive Web App" category
4. Run audit

## Installation Testing

### Desktop Chrome

1. Look for install icon in address bar
2. Or wait 30 seconds for install toast
3. Click install and app opens in standalone window

### Mobile Devices

- **Android**: Chrome shows "Add to Home Screen" banner
- **iOS**: Safari > Share > Add to Home Screen

## Offline Testing

1. Install the PWA
2. Open DevTools > Network > Check "Offline"
3. Navigate around - cached pages work
4. Uncached pages show offline page

## Deployment Checklist

### Vercel Deployment

- [x] HTTPS enabled automatically
- [x] Service worker at root path
- [x] Manifest linked in HTML head
- [x] Icons accessible at root

### Production Requirements

- HTTPS (handled by Vercel)
- Valid SSL certificate
- Service worker scope at root
- Manifest with required fields

## Common Issues

### Service Worker Not Registering

- Check console for errors
- Ensure HTTPS in production
- Clear browser cache and retry

### Install Prompt Not Showing

- Must be on HTTPS
- User hasn't already installed
- Browser supports PWA installation
- Wait 30 seconds after page load

### Updates Not Working

- Service worker caches may be stale
- Hard refresh: Ctrl+Shift+R
- Clear site data in DevTools

## Future Enhancements

### Push Notifications

Structure is ready in service worker:

```javascript
self.addEventListener('push', (event) => {
  // Implementation ready
});
```

### Background Sync

Could add for offline weight logging:

```javascript
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-weights') {
    // Sync offline data
  }
});
```

### Enhanced Caching

Current: Basic cache-first strategy
Future: Network-first for API calls

## Monitoring

### Analytics Events

PWA events are tracked:

- Install prompt shown
- App installed
- Update available

### Performance Metrics

- Service worker registration time
- Cache hit rate
- Offline page views

## Browser Support

| Feature        | Chrome | Safari | Firefox | Edge |
| -------------- | ------ | ------ | ------- | ---- |
| Service Worker | ✅     | ✅     | ✅      | ✅   |
| Install        | ✅     | ⚠️     | ❌      | ✅   |
| Push           | ✅     | ⚠️     | ✅      | ✅   |
| Offline        | ✅     | ✅     | ✅      | ✅   |

⚠️ = Partial support
❌ = Not supported

## Resources

- [web.dev PWA Guide](https://web.dev/progressive-web-apps/)
- [Chrome PWA Docs](https://developer.chrome.com/docs/workbox/)
