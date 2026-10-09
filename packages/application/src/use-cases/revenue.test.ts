import { describe, expect, it } from 'vitest'
import { fullDeps, invoice } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeIssueInvoice } from '@/use-cases/invoices'
import { makePayroll } from '@/use-cases/payroll'
import { makeRevenue } from '@/use-cases/revenue'
import { addMonths } from '@/use-cases/shared'

const PREVIOUS_YEAR = Array.from({ length: 12 }, (_, i) =>
  addMonths('2026-10', -1 - i),
)

async function seedYear(deps: ReturnType<typeof fullDeps>) {
  const revenue = makeRevenue(deps)
  const payroll = makePayroll(deps)
  for (const month of PREVIOUS_YEAR) {
    await revenue.save(TENANT, month, {
      domesticCents: 1_600_000,
      exportCents: 0,
    })
    await payroll.save(TENANT, month, {
      proLaboreCents: 450_000,
      salariesCents: 0,
      fgtsCents: 0,
    })
  }
  return revenue
}

describe('revenue', () => {
  it('leaves the ISS rate open until a year of payroll exists', async () => {
    const deps = fullDeps()
    await deps.invoices.save(invoice({ id: 'i', competence: '2026-09' }))
    await deps.invoices.save(
      invoice({ id: 'x', competence: '2026-08', isExport: true }),
    )
    const sheet = await makeRevenue(deps).sheet(TENANT)
    expect(sheet.months).toHaveLength(12)
    expect(sheet.months[0]).toMatchObject({
      month: '2026-09-01',
      domestic: { cents: 100000 },
      entered: false,
    })
    expect(sheet.domesticRbt12.cents).toBe(100000)
    expect(sheet.exportRbt12.cents).toBe(100000)
    expect([sheet.annex, sheet.issRatePercent]).toEqual(['V', null])
  })

  it('prices ISS from the domestic RBT12 of entered months and invoices', async () => {
    const deps = fullDeps()
    const revenue = await seedYear(deps)
    const sheet = await revenue.sheet(TENANT)
    expect(sheet.months.every(month => month.entered)).toBe(true)
    expect(sheet.domesticRbt12.cents).toBe(19_200_000)
    expect([sheet.annex, sheet.issRatePercent]).toEqual(['III', 2.02])
    await deps.invoices.save(invoice({ id: 'i', competence: '2026-09' }))
    const mixed = await revenue.sheet(TENANT)
    expect(mixed.months[0]?.domestic.cents).toBe(1_700_000)
  })

  it('sends the rate with a domestic invoice and none with an export', async () => {
    const deps = fullDeps()
    await seedYear(deps)
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Client Inc',
      taxId: null,
      country: 'US',
    })
    const issue = makeIssueInvoice(deps)
    await deps.invoices.save(
      invoice({ id: 'd', status: 'DRAFT', competence: '2026-10' }),
    )
    await deps.invoices.save(
      invoice({
        id: 'e',
        status: 'DRAFT',
        competence: '2026-10',
        isExport: true,
      }),
    )
    await issue(TENANT, 'd')
    await issue(TENANT, 'e')
    expect(deps.issuer.drafts.map(draft => draft.issRatePercent)).toEqual([
      2.02,
      null,
    ])
  })
})
