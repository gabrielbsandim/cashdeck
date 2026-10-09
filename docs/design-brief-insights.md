# Design brief: insights redesign (for Claude Design)

Second round, built on the delivered Cashdeck Foundation and Screens files under
`design/`. Attach those files to the Claude Design project, then paste the
prompt below. The first brief is [design-brief.md](./design-brief.md).

---

## Prompt

> You already designed **Cashdeck**, a self-hosted personal and small company
> finance app for Brazil, built in Flutter (Material 3). The attached files are
> the current Foundation (tokens, Geist and Geist Mono, components prefixed `Cd`)
> and Screens. This round redesigns the app around **insights you understand at
> a glance**: opening the app should change how I think about money today. Keep
> every existing token name and component; extend them, and say which ones
> change.
>
> **Goal of the round.** Today the home shows numbers; it should show
> direction. Every card answers "am I better or worse than last month, and what
> is already committed?" in under two seconds, with a big number, a short
> comparison and one small chart.
>
> **Visual direction.**
> - Dark theme becomes the hero: true black background (OLED), surfaces as
>   layered near-blacks, one vivid accent, big tabular numbers, cards with large
>   radii (20 to 24dp). Light theme stays first class with the same hierarchy.
> - A subtle animated gradient glow at the top of the home, tinted by the active
>   entity (Pessoal, Empresa, Consolidado).
> - Motion with intent: numbers count up on first show, charts draw from left to
>   right, a card expands into its screen (container transform), bars grow from
>   the baseline, a stacked bar fills segment by segment. Under 400ms, spring
>   based, all of it off with reduced motion.
> - Institution logos: a circular logo slot that renders the bank's image at
>   runtime and falls back to a monogram. Mockups use monograms and fictional
>   institutions only (the project is open source).
>
> **Navigation (replaces the current five tabs).**
> - Tabs: **Início, Transações, Pagar, Análises**. Pagar keeps its count badge.
> - Chat leaves the tab bar and becomes a floating **"Pergunte ao Cashdeck"**
>   bar docked above the navigation, on every main tab. Tapping it opens the
>   chat full screen.
> - The **Mais** tab is removed. The avatar at the top left opens **Ajustes**,
>   organized in four groups:
>   1. **Conexões:** connected accounts (with "connect by item id" inside it),
>      payment rails, bill capture sources.
>   2. **Pagamentos:** autopay rules, safety caps, the kill switch.
>   3. **Empresa** (only with a company entity): invoices, payroll, transfers
>      PJ to PF, accountant export.
>   4. **Conta e aparência:** theme, language, privacy, alerts, about, sign out.
>   Daily screens (cards, budgets, goals, subscriptions, installments, cash
>   flow) live in Início and Análises, never in Ajustes. "Card bill without
>   Open Finance" moves inside the Cards screen.
>
> **Início (home), top to bottom.**
> 1. Header: avatar, entity switcher, privacy eye, alerts bell.
> 2. **Total balance**, large, with "em N contas" and a stacked colored bar (one
>    segment per institution). Tapping it opens **Saldo por conta**.
> 3. **Gastos do mês:** the month's spend, "↑ 12% vs mês passado" (or ↓, with
>    tone and icon), and a cumulative spend line for this month over a dashed
>    line for the previous month, with a "hoje" marker. A period toggle 1s, 1m,
>    6m, 1a. Below it, the top 3 merchants of the period.
> 4. **Por categoria:** one segmented horizontal bar, the 3 biggest categories
>    with icon, amount, % of the total and the change vs last month, "ver
>    todas".
> 5. **Fluxo do mês:** two horizontal bars, entradas and saídas, and the
>    result ("sobrou R$ X" or "faltou R$ X"). The 30 day forecast stays only as
>    a one line warning when the balance would go below the reserve floor.
> 6. **Widget grid**, two columns of small cards, each one tappable into its
>    screen: Fatura atual (amount, due in N days), Parcelamentos (committed
>    next month), Assinaturas (monthly total), Limite usado (ring with %),
>    Contas a pagar (next 7 days), Metas (closest goal). "Editar widgets" lets
>    me reorder and hide them.
>
> **Saldo por conta (balance per account).** Total on top, the stacked bar,
> then one row per account: logo, institution and account name, type
> (checking, savings, reserve, card), % of the total and balance, last sync time
> and a status dot (synced, syncing, needs reconnect with an action). A
> "Conectar conta" button. Below, the latest transactions of the selected
> account. Group by Pessoal and Empresa in Consolidado.
>
> **Análises (new tab), the month by month view.** A month selector at the top
> (swipe between months) and a 6m / 12m toggle.
> 1. **Entradas vs saídas por mês:** paired bars per month with the result line
>    on top; tapping a month selects it.
> 2. **Taxa de poupança:** % of income kept this month vs the 3 month average,
>    as a big number and a small trend line.
> 3. **O que mudou:** the categories that rose and fell the most vs the
>    average, as a list with arrows and amounts.
> 4. **Custo fixo:** subscriptions, recurring bills and installments as a share
>    of income, as a ring with the three parts.
> 5. **Quanto sobra até o fim do mês:** balance minus bills due minus the open
>    card bill, with each part listed.
> 6. **Empresa para pessoal** (only with a company): what moved PJ to PF this
>    month and what went to taxes.
> 7. **Insights:** two or three short sentences generated from the data, like
>    "Delivery está 30% acima da sua média" or "Março já tem R$ 1.200 em
>    parcelas". Each has an icon, a tone and a tap target.
>
> **Parcelamentos (installments).**
> - Top: "Comprometido em <mês>" with a big amount and bars for the next 12
>   months; tapping a bar switches the month.
> - List of purchases: merchant logo or category icon, card ending, "7 de 12",
>   installment amount, a progress bar paid vs remaining, "falta R$ X" and the
>   month of the last installment. Filters: all cards or one card; ending soon.
> - Detail: total, paid, remaining, a vertical timeline of every installment
>   (paid, current, future) and the purchase transaction.
>
> **Assinaturas (subscriptions).**
> - Top: monthly commitment and the yearly equivalent, change vs last month.
> - List: logo, name, amount, "cobrado todo dia X", status this month (paid,
>   upcoming, late), price change flag.
> - A calendar view of the month with a dot on each charge day.
> - Detected subscriptions arrive as suggestions to confirm or dismiss; any
>   transaction can be marked "recorrente" from its detail.
>
> **Cartões (cards).** Two tabs:
> - **Faturas:** current bill amount, closing and due dates, "vence em 6 dias",
>   bars of the last 6 bills, the bill's transactions.
> - **Limites:** a ring with % of the total limit used, then per card: used,
>   available, limit, with a bar.
>
> **Pagar (bills) additions.** A month calendar at the top showing bills, card
>   bills and subscriptions on each day, with a tone per status. A bill paid by
>   auto debit shows "débito automático" and leaves the overdue groups once its
>   due date passes.
>
> **Transações.**
> - Row: category icon with the institution logo as a small badge at the
>   bottom right, description, category, amount, and "3/10" for installments.
> - Search, chips Entradas, Saídas, Todas, then filters (account, category,
>   period). Groups Hoje, Ontem, then dates.
> - Detail: account and card ending, installment "3 de 10" with a link to the
>   installment, "marcar como recorrente", category with the AI suggestion,
>   note.
>
> **States for every new card and screen:** first load skeleton shaped like the
> content, empty (with what to do next, for example "conecte um cartão para ver
> seus parcelamentos"), error with retry, privacy mode with every amount as
> `R$ ••••`. While categories load, a transaction row shows a skeleton chip,
> never a placeholder category name.
>
> **Contract kept from the first brief:** 360dp first, 48dp touch targets, AA
> contrast in both themes, no meaning by color alone (icon plus label), true
> minus sign (U+2212), `R$ 1.234,56`, `dd/MM`, copy in pt-BR first and English
> second, fictional data only.
>
> **Deliverables:** the token changes (dark OLED palette, new radii, chart and
> motion tokens), the new components (`CdBalanceBar`, `CdComparisonLine`,
> `CdCategoryBar`, `CdFlowBars`, `CdMonthBars`, `CdWidgetTile`,
> `CdInstitutionLogo`, `CdProgressRing`, `CdInstallmentTimeline`,
> `CdCalendarMonth`, `CdAskBar`, `CdInsightRow`, or better names you propose),
> and every screen above in dark and light, with a short motion spec per
> screen.

---

## Data the redesign needs

| Screen | Source |
|---|---|
| Saldo por conta, logos | Accounts exist; the institution image and color come from the Pluggy connector and must be stored |
| Gastos do mês, categories, flow, Análises | Monthly aggregates over existing transactions |
| Parcelamentos, "3/10" | Pluggy `creditCardMetadata` on card transactions, not stored yet |
| Assinaturas | Recurrence detection over transactions plus a manual flag |
| Limites | Card limits from Pluggy accounts |
