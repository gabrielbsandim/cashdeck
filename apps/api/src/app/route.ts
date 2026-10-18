import { publicPage } from '@/server/api/public-page'

export function GET() {
  return publicPage('Cashdeck', [
    'Cashdeck is a private finance app for a single household: accounts, cards, bills and taxes in one place.',
    'Access is by invitation only. Read the <a href="/privacy">privacy policy</a>.',
  ])
}
