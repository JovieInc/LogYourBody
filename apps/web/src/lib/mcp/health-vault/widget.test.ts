import { HEALTH_VAULT_API_ORIGIN } from './constants';
import { auditHealthVaultWidgetBundle } from './widget-privacy';
import { healthVaultWidgetDocument } from './widget';

function parts(origin: string) {
  const html = healthVaultWidgetDocument(origin);
  const body = html.slice(html.indexOf('<body>') + 6, html.indexOf('<script>'));
  const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
  return { html, body, script };
}

async function flush() {
  await new Promise((resolve) => setTimeout(resolve, 0));
  for (let i = 0; i < 8; i += 1) await Promise.resolve();
}

describe('health vault widget bundle', () => {
  it('never forwards health values through the host bridge', () => {
    const html = healthVaultWidgetDocument(HEALTH_VAULT_API_ORIGIN);
    expect(auditHealthVaultWidgetBundle(html)).toEqual([]);
    expect(auditHealthVaultWidgetBundle(`${html}\nbridge.setWidgetState({})`)).toContain(
      'setWidgetState',
    );
    expect(
      auditHealthVaultWidgetBundle(
        'bridge.callTool("share_summary_with_chatgpt", { consentId: id, weightKg: 1 })',
      ),
    ).toContain('callTool includes a health value');
    expect(auditHealthVaultWidgetBundle('bridge.callTool("other", { consentId: "x" })')).toContain(
      'callTool must pass only a consent id to share_summary_with_chatgpt',
    );
    expect(
      auditHealthVaultWidgetBundle(
        'bridge.callTool("share_summary_with_chatgpt", { consentId: "x" }); bridge.callTool("share_summary_with_chatgpt", { consentId: "y" });',
      ),
    ).toContain('callTool count 2');
    expect(auditHealthVaultWidgetBundle('el.innerHTML = row.bodyFatPercent')).toContain(
      'innerHTML',
    );
  });

  it('loads measurements from LogYourBody and shares only a consent id', async () => {
    const origin = 'https://www.logyourbody.com';
    const { body, script } = parts(origin);
    document.body.innerHTML = body;
    const requests: Array<{ url: string; body: string }> = [];
    const callTool = jest.fn();
    (window as unknown as { openai: unknown }).openai = {
      toolResponseMetadata: { mcp_tool_result: { _meta: { viewHandle: 'vh_widget_handle' } } },
      callTool,
    };
    const jsonResponse = (body: unknown, status = 200) => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    });
    const fetchMock = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url =
        typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      const requestBody = typeof init?.body === 'string' ? init.body : '';
      requests.push({ url, body: requestBody });
      if (url.endsWith('/api/health-vault/view')) {
        return jsonResponse({
          confirmToken: 'ct_widget_confirm',
          dexa: [
            { id: 'dx1', measuredOn: '2026-01-01', bodyFatPercent: 17.3417, leanMassKg: 60.5 },
          ],
          photos: [
            { id: 'ph_SENTINEL', imageUrl: 'https://photos.logyourbody.com/sentinel.png' },
            { id: 'evil', imageUrl: 'https://evil.example/secret.png' },
          ],
          weighIns: [{ id: 'w1', measuredOn: '2026-02-02', weightKg: 81.2229 }],
        });
      }
      if (url.endsWith('/api/health-vault/consents')) {
        return jsonResponse({ consentId: 'co_widget_consent', bodyFatPercent: 17.3417 });
      }
      return jsonResponse({ error: 'no' }, 404);
    });
    window.fetch = fetchMock as typeof fetch;

    new Function(script)();
    await flush();

    expect(document.getElementById('lyb-status')?.textContent).toBe('Loaded from LogYourBody.');
    expect(requests.map((item) => new URL(item.url).host)).toEqual(['www.logyourbody.com']);
    const images = [...document.querySelectorAll('img')].map((img) => img.getAttribute('src'));
    expect(images).toEqual(['https://photos.logyourbody.com/sentinel.png']);
    expect(document.body.innerHTML).not.toContain('evil.example');

    const box = document.querySelector('input[value="body_fat"]') as HTMLInputElement;
    box.checked = true;
    document
      .getElementById('lyb-share')
      ?.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flush();

    expect(JSON.parse(requests[1]?.body ?? '{}')).toEqual({
      confirmToken: 'ct_widget_confirm',
      fields: ['body_fat'],
    });
    expect(callTool).toHaveBeenCalledTimes(1);
    expect(callTool).toHaveBeenCalledWith('share_summary_with_chatgpt', {
      consentId: 'co_widget_consent',
    });
    expect(JSON.stringify(callTool.mock.calls)).not.toContain('17.3417');
  });
});
