import { publicPage } from '@/server/api/public-page'

export function GET() {
  return publicPage('Cashdeck privacy policy', [
    'Cashdeck is a private finance app used by a single household. It is not offered to the public.',
    'When you connect a Gmail account, Cashdeck asks for read-only access and uses it only to find bills, such as boletos, tax guides and Pix charges, in your messages. It reads the amount, due date, payee and payment code, and keeps the bill document. It never sends, changes or deletes mail.',
    'What Cashdeck reads is stored in its own database and is used only to show and pay your bills. It is not sold, shared with third parties or used for advertising. Cashdeck use of data received from Google APIs adheres to the Google API Services User Data Policy, including the Limited Use requirements.',
    'You can disconnect the mailbox at any time in the app, under capture sources, which deletes the stored access token. You can also revoke access in your Google account settings.',
  ])
}
