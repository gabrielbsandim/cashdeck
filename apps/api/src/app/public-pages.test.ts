import { describe, expect, it } from 'vitest'
import { GET as home } from '@/app/route'
import { GET as privacy } from '@/app/privacy/route'
import { GET as termsPage } from '@/app/terms/route'

describe('public pages', () => {
  it('serves the home page and the privacy policy as HTML', async () => {
    const homePage = home()
    expect(homePage.headers.get('content-type')).toContain('text/html')
    expect(await homePage.text()).toContain('href="/privacy"')

    const policy = await privacy().text()
    expect(policy).toContain('<title>Cashdeck privacy policy</title>')
    expect(policy).toContain('read-only access')
    expect(policy).toContain('Limited Use')

    const terms = await termsPage().text()
    expect(terms).toContain('<title>Cashdeck terms of service</title>')
    expect(terms).toContain('href="/privacy"')
  })
})
