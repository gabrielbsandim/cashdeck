import { afterEach, describe, expect, it, vi } from 'vitest'
import type * as NextServer from 'next/server'

const { afterMock } = vi.hoisted(() => ({ afterMock: vi.fn() }))

vi.mock('next/server', async importOriginal => ({
  ...(await importOriginal<typeof NextServer>()),
  after: afterMock,
}))

const { defer } = await import('@/server/api/webhook')

afterEach(() => {
  afterMock.mockReset()
  vi.restoreAllMocks()
})

describe('defer', () => {
  it('hands the task to after() inside a request', async () => {
    const task = vi.fn(async () => 'done')
    await defer(task, 'test')
    expect(task).not.toHaveBeenCalled()
    await afterMock.mock.calls[0]?.[0]()
    expect(task).toHaveBeenCalledOnce()
  })

  it('runs inline outside a request and reports a failure', async () => {
    afterMock.mockImplementation(() => {
      throw new Error('outside a request scope')
    })
    const logged = vi
      .spyOn(console, 'error')
      .mockImplementation(() => undefined)
    await defer(async () => {
      throw new Error('boom')
    }, 'test')
    expect(logged).toHaveBeenCalledWith('[test] Error: boom')
  })
})
