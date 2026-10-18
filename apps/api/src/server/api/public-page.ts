// Google's consent screen needs a public home page and privacy policy to
// publish the Gmail client, so these two pages are plain HTML with no session.
export function publicPage(title: string, paragraphs: readonly string[]) {
  const body = paragraphs.map(text => `<p>${text}</p>`).join('\n')
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem;color:#1a1a1a;background:#fff}</style>
</head>
<body>
<h1>${title}</h1>
${body}
</body>
</html>`
  return new Response(html, {
    headers: { 'content-type': 'text/html; charset=utf-8' },
  })
}
