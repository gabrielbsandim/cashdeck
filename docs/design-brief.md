# Design brief: Cashdeck (for Claude Design)

Copy the prompt below into Claude Design. The repository is not public yet, so the
prompt is self-contained. Product context lives in [plan.md](./plan.md).

---

## Prompt

> You are designing **Cashdeck**, an open-source, self-hosted personal finance
> **mobile app built in Flutter** (Material 3). It is the sibling of **Lifedeck**
> (a life organizer) in the same family: "deck" means a control panel, calm command
> over your money held in the palm of your hand. Design high-fidelity screens I can
> translate 1:1 into Flutter `ThemeData`, `ColorScheme` and `ThemeExtension` tokens
> plus reusable widgets.
>
> **Product in one line:** see every account in one place, capture every bill from
> any channel, let the app pay it automatically (with a human fallback that is
> always one tap away), run a small company's invoices and taxes, and ask an AI
> about any of it.
>
> **Who it is for:** a person in Brazil managing their personal finances (PF) and,
> optionally, a small company (PJ). They connect banks through Open Finance, also
> keep accounts with no Open Finance (imported by hand), and want bills paid
> without thinking about them. They check the app on the phone, quickly, several
> times a week. The app is open source, so every sample in the mockups uses
> fictional people, companies and amounts, and institutions appear as neutral
> monogram avatars, never real bank logos.
>
> **Brand and mood:** trustworthy, calm, precise, modern. Money is serious but the
> app is not cold. Generous whitespace, rounded corners (8/12/16), soft elevation,
> a typeface with **tabular figures** that will be bundled as an asset (Geist or
> Inter, your call). Propose the Cashdeck accent color yourself: it must feel of
> the same family as Lifedeck (indigo `oklch(0.58 0.2 280)`) without copying it,
> and it **must not collide** with the money semantics below.
>
> **Money semantics (define tokens for each):** income, expense, transfer between
> own accounts (neutral, never counted twice), pending, scheduled, awaiting
> approval in the bank, paid, failed, overdue. Never carry meaning by color alone:
> every status has an icon and a label. Amounts in BRL formatted `R$ 1.234,56`,
> negative amounts with a sign, foreign currency shown with its code and the
> converted BRL value. A **privacy toggle** hides every amount (`R$ ••••`).
>
> **Light and dark themes are both first class.** Deliver every screen in both.
>
> **Global elements:**
> - **Entity switcher** at the top: `Pessoal`, `Empresa`, `Consolidado`. It
>   scopes every screen. Each entity has a subtle identity (tint or badge).
> - Bottom navigation with five destinations: Início, Transações, Contas a pagar,
>   Chat, Mais.
> - A global **kill switch** state: when automatic payments are paused, a
>   persistent banner says so.
>
> **Work in two stages. Do Stage 1 first, then continue to Stage 2 in the same
> flow.**
>
> **Stage 1: foundation**
> 1. **Token sheet:** colors (light and dark, with OKLCH and hex), money semantic
>    colors, spacing scale, radii, typography scale (with tabular numerals for
>    amounts), elevation, motion durations and easings.
> 2. **Brand:** the Cashdeck mark (works at 24dp and as an app icon, adaptive
>    Android icon with a safe zone, iOS icon), wordmark, splash screen.
> 3. **Component sheet with all states** (default, pressed, focused, disabled,
>    loading, error): amount text (sizes, positive, negative, hidden), button
>    variants, text field, currency input, search field, chips and filters,
>    entity switcher, account card, transaction row, bill card with its payment
>    status, payment ladder stepper (see below), category icon and chip, budget
>    progress bar, segmented control, bottom sheet, confirm sheet, toast, inline
>    banner, list row, empty state, skeleton, error state, chart primitives (bar,
>    line, donut), copyable code field (boleto line and Pix copy and paste).
> 4. **Home (Início)** for the PF entity: total balance, reserve balance and its
>    yield, bills due in the next 7 days, cash flow forecast for 30 days, budget
>    highlights, latest alerts.
>
> **The payment ladder (the heart of the app).** Every bill is paid by walking
> three steps: **1 Automatic** (the app pays through a bank API), **2 Approval in
> the bank** (the app prepares the payment, the user approves it in the bank's
> internet banking), **3 Assisted** (the app shows the code or Pix payload, the
> user pays and marks it paid). A failure moves one step down, never to silence.
> Design a stepper or timeline that shows which step a bill is on, every attempt
> with time and reason, and the next action. Step 3 must feel like a reliable
> safety net, not an error.
>
> **Stage 2: remaining screens** (built on the Stage 1 tokens and components)
> 1. **Onboarding and setup:** welcome, create the personal entity, optionally add
>    a company (tax id, regime), connect institutions (Open Finance), add a manual
>    institution, choose the reserve account that funds bills, connect payment
>    rails with a clear status per rail, set safety caps.
> 2. **Transactions:** list with search, filters (account, category, period,
>    entity), grouped by day; transaction detail with category, AI suggested
>    category and "always categorize like this" (creates a rule), split, note,
>    attachment.
> 3. **Accounts:** accounts grouped by institution with sync status and last
>    sync time; account detail; credit card with the open and closed bill,
>    installments and limit; manual bill import (upload a PDF, review the
>    extracted draft line by line, confirm).
> 4. **Contas a pagar (bills):** inbox of captured bills with a source badge
>    (email, shared file, camera, chat, DDA); bill detail with the payment ladder;
>    capture flows: camera barcode scanner, review screen after sharing a PDF to
>    the app; a calendar of the next 30 days showing when the reserve is used.
> 5. **Empresa (company):** invoices (NFS-e) list with status; issue invoice
>    (domestic client, or service export with currency and rate); recurring
>    invoice templates and the monthly draft waiting for approval; tax calendar
>    (DAS, DARF) with each guide's payment status; monthly tax estimate;
>    reconciliation (invoice matched to its receipt, receipts without an invoice,
>    a month without a tax guide).
> 6. **Planning:** budgets by category with 80% and 100% thresholds; recurrences
>    and subscriptions (price change and duplicate flags); goals ("caixinhas")
>    with target, deadline and projected completion; investments and net worth
>    timeline per entity and consolidated.
> 7. **Chat:** multimodal composer (text, photo, camera, PDF, audio recording);
>    rich answer cards (transaction list, chart, bill created from an
>    attachment, monthly summary); a **two-step confirmation card** for any action
>    with side effects (pay, schedule, issue invoice, create rule).
> 8. **Alerts:** inbox grouped by day; settings to mute each alert type.
> 9. **Mais (settings):** entities, institutions, payment rails, safety caps and
>    kill switch, theme (system, light, dark), language, privacy, about.
> 10. **States for every list:** first load skeleton, empty, error with retry,
>     offline, syncing.
>
> **Interaction and motion:** subtle, under about 250ms, spring based; one
> satisfying moment when a bill turns paid; respect reduced motion.
>
> **Accessibility contract:** designed at **360dp** wide first (no horizontal
> scroll), touch targets of at least 48dp, body text at least 14sp, AA contrast in
> both themes, works with large system font scale, nothing under the system bars.
>
> **Internationalization:** copy in Brazilian Portuguese first, English second;
> every string short and key-able, no text baked into images. Dates `dd/MM`,
> week starts on Sunday.
>
> **Deliverables:** the token sheet, brand, component sheet and all screens above
> in light and dark, organized so each token maps to a Flutter name (for example
> `AppColors.income`, `AppSpacing.md`, `AppRadius.lg`, `AppTextStyles.amountLg`)
> and each component maps to one widget. Give dp values, not px guesses.

---

## After Claude Design delivers

1. Save the `.dc.html` files under `design/`.
2. Replace the placeholder tokens in `apps/mobile/lib/core/theme/` with the
   delivered ones, light and dark.
3. Build the component sheet as widgets under `apps/mobile/lib/core/widgets/`,
   then restyle the screens.
4. Run `apps/mobile/tool/check.sh`.
