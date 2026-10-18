import { publicPage } from '@/server/api/public-page'

export function GET() {
  return publicPage('Cashdeck terms of service', [
    'Cashdeck is a private finance app for a single household. Access is by invitation only, and using it means accepting these terms.',
    'Cashdeck organizes accounts, cards, bills and taxes and can prepare payments, but every payment it makes follows the rules you set or a confirmation you give. You remain responsible for checking amounts, due dates and payees before money leaves your accounts.',
    'Balances, forecasts and alerts come from banks, card apps, mailboxes and documents you connect. They can be late, incomplete or wrong, so they are an aid and not financial, tax or legal advice.',
    'You can disconnect any source or stop using Cashdeck at any time. How your data is handled is described in the <a href="/privacy">privacy policy</a>.',
    'The app is provided as is, without warranties, and these terms can change as the app does.',
  ])
}
