# foothills-deploy

Public transfer repo so the Foothills VM can pull files with a plain `curl`,
with no credentials on the command line.

## The eight new SEO pages — live now

```
curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-seo.sh -o /tmp/fh-seo.sh && sudo sh /tmp/fh-seo.sh
```

Installs the eight pages and the updated sitemap, adds the three new links to
the footer on every page, then asks the server itself whether each new URL
really returns 200 — and whether the home page still does.

Safe to run twice. The footer edit is guarded, so a second run cannot duplicate
the links.

## The loan calculator — behind a password

```
curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-calculator.sh -o /tmp/fh-calc.sh && sudo sh /tmp/fh-calc.sh
```

It asks you to choose a password. **Type it into the terminal — do not put it in
chat.** Username is `foothills`.

This one edits the nginx config, which is the only thing here that could take
the site down. So it backs the config up, runs `nginx -t` **before** reloading,
puts the original straight back if that check fails, and finishes by proving the
public site still answers.

Ends up at `https://foothillslivestock.ca/preview/livestock-loan-calculator.html`
— 401 without the password, not in the sitemap, and served with a
`X-Robots-Tag: noindex, nofollow` header.

To unpublish later: delete the block marked `# foothills-preview-auth` from the
nginx config and reload.


## Google Analytics — finish the rollout

```
curl -sSLf https://raw.githubusercontent.com/anirudhatalmale6-alt/foothills-deploy/main/deploy-analytics.sh -o /tmp/fh-ga.sh && sudo sh /tmp/fh-ga.sh
```

The GA4 tag is in the repo on all 30 pages but is only **live** on the eight new
ones. This puts it on the other 15, and installs `fh-events.js`, which tracks the
things that actually convert on this site:

| Event | Fires when |
|---|---|
| `phone_click` | somebody taps a phone number — the real conversion here |
| `form_open` | an application or claim form is opened |
| `chat_open` | the chat widget is opened |
| `calculator_use` | somebody uses the loan calculator |

There are no web forms on this site, so without these events GA can only report
visits, never enquiries.

Does not touch the in-house tracker in `fh-analytics.js`. Safe to run twice.

## What is in here

| Path | What |
|---|---|
| `site/*.html` | the eight new SEO pages |
| `site/sitemap.xml` | 23 urls — the calculator is deliberately not listed |
| `site/preview/livestock-loan-calculator.html` | the calculator |
| `deploy-seo.sh` | installs the public pages |
| `deploy-calculator.sh` | installs the calculator and locks it |
| `deploy-analytics.sh` | finishes the GA4 rollout and adds event tracking |
| `site/assets/fh-events.js` | the event tracker |
| `deploy.sh`, `foothills-logo.png` | the earlier 1996 logo deploy — left in place on purpose |

`deploy.sh` and the logo stay because a `curl -o` against a deleted file writes
the 404 body straight over the target. Leaving them costs nothing.
