# Design review: round 1

Reviewed on 2026-10-08 against [design-brief.md](./design-brief.md) and
[plan.md](./plan.md). Files: `design/Cashdeck Foundation.dc.html`,
`design/Cashdeck Screens - Money.dc.html`,
`design/Cashdeck Screens - Company.dc.html`.

Every item of the brief is delivered, in light and dark, with Flutter token names
and AA contrast notes. What follows is what contradicts the plan or is missing.

## Follow-up prompt for Claude Design

> Great work. Keep everything as is and fix or add only the items below, in light
> and dark, reusing the Foundation tokens and widgets.
>
> **Fix**
> 1. **The personal entity has no step 2.** Bank approval exists only for the
>    company. Add a `CdPaymentLadder` variant where step 2 shows as "Não disponível
>    para esta conta" (muted, skipped), and redo the PF examples (Aluguel on Home,
>    B2, alerts) so a PF failure goes from step 1 straight to step 3. Keep one
>    step 2 example on a company bill.
> 2. **Safety caps confirm in the app, not in the bank.** O8 and M2 say "acima
>    deles, o pagamento desce para aprovação no banco". Above a cap, a new payee
>    or an unusual amount, the app asks for an in-app confirmation (the
>    `CdConfirmSheet` with biometrics); without it the bill goes to step 3.
> 3. **Tax guides never go to bank approval.** On E4 the DARF shows "Aprovar no
>    banco"; the bank-approval rail accepts only boleto and Pix. Tax guides are
>    step 1 or step 3 only.
> 4. **Privacy mode leaks amounts:** the Home alert "R$ 624 de R$ 600" stays
>    visible with privacy on. Every amount, including inside alerts, chat and
>    charts' labels, must hide.
> 5. **"Desfazer" on "Energia Lumina paga"** cannot undo a real payment. Show
>    undo only after a manual "Marcar como pago".
> 6. **Audio transcription is not local.** C4 says "Transcrito no seu servidor ·
>    nada sai daqui", but the AI provider is external. Use "Transcrito pela IA
>    configurada no seu servidor".
> 7. **Bill capture is not an inbound e-mail address.** Empty states say
>    "Encaminhe boletos para contas@cashdeck.casa". Capture reads the user's own
>    mailbox after they connect it. Change the copy to "Conecte seu e-mail,
>    compartilhe um PDF ou escaneie".
> 8. The Aluguel alert reason ("limite diário do Pix") disagrees with B2 ("acima
>    do limite por pagamento"). Use one.
>
> **Add**
> 9. **Sign in to the server:** after the server address on O1, a sign-in or
>    first-user creation screen (e-mail and password), plus the app unlock screen
>    with biometrics.
> 10. **Open Finance by item id:** the free aggregator tier has no in-app
>     connect widget. Add a variant of O4 where the user pastes an item id
>     copied from the aggregator dashboard, with a "Como encontrar" help sheet
>     and a validation state.
> 11. **Capture sources setup:** connect a mailbox (OAuth), see the last scan and
>     how many bills it found; turn the company DDA on or off.
> 12. **Rails per entity and their credentials:** O7 per entity (Pessoal rails
>     differ from Empresa rails), and a rail detail screen to upload a client
>     certificate (.pfx or .crt plus key), paste an API key, see the status and
>     run a test. For the personal entity, show the funding step: on the due
>     date morning the reserve sends one Pix to the payer account sized to that
>     day's bills.
> 13. **Invoice issuer setup:** choose the issuer, upload the A1 certificate
>     (with expiry date and an expiring-soon state), municipal registration,
>     default service code, and a test emission.
> 14. **Home for Empresa and for Consolidado:** company cash, taxes due, invoices
>     to approve, receipts without an invoice; consolidated net view where
>     transfers between entities do not count twice.
> 15. **Manual credit card bill import:** for a card without Open Finance, a
>     foreign-currency card bill (USD lines, rate and IOF) imported at each
>     closing, reviewed line by line, then turned into a bill to pay.
> 16. **Monthly payroll input for Fator R:** pro-labore and payroll for the
>     month, entered by hand, feeding E5.
> 17. **Profit distribution:** a transfer from Empresa to Pessoal labelled
>     "Distribuição de lucros", neutral in both entities.
> 18. **Receipt viewer** for a paid bill (proof from the rail or an uploaded
>     file), and the monthly export for the accountant (period, contents,
>     share).
> 19. Remove "Restaurar de um backup" from O1; backups are done on the server.

## Round 2

Delivered on 2026-10-08 as `design/Cashdeck Screens - Additions.dc.html` plus
updated Foundation, Money and Company files. Items 1 to 19 are addressed. One
leftover: a Foundation alert still reads "Aluguel desceu para aprovação no
banco" for a personal bill; the corrected Home alert is the reference.

## After the round

Save the updated `.dc.html` files under `design/`, then implement tokens and the
component sheet in `apps/mobile/lib/core/`.
