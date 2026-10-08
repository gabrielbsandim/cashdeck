# Design and components

Screens are designed in Claude Design first (brief in
[`../../../docs/design-brief.md`](../../../docs/design-brief.md)) and
implemented here second. The tokens and components below come from the
Cashdeck Foundation sheet; the screens follow Cashdeck Screens and its
Additions file, all under `design/` at the repository root.

## Tokens

`lib/core/theme/`:

| File                    | Holds |
| ----------------------- | ----- |
| `app_palette.dart`      | `AppPalette`, a `ThemeExtension` with `light` and `dark`: Material 3 surfaces, containers, outline and text roles |
| `app_money_colors.dart` | `AppMoneyColors` (one `ToneColors` per `MoneyTone`, plus `paid`, `failed` shortcuts) and `AppEntityColors` (personal, company, consolidated) |
| `money_tone.dart`       | `MoneyTone`: income, expense, transfer, pending, scheduled, awaitingApproval, paid, failed, overdue, assisted, neutral |
| `app_spacing.dart`      | `AppSpacing` (4dp grid, 16dp screen gutter, 48dp touch floor), `AppRadius`, `AppElevation`, `AppMotion` |
| `app_text_styles.dart`  | The type scale in Geist; amounts and codes use Geist Mono with tabular figures |
| `app_theme.dart`        | `AppTheme.light()` and `AppTheme.dark()`, both built from one `_build` with the three extensions |

Screens read colors only through `context.palette`, `context.money` and
`context.entities` (`context.tone(MoneyTone.paid)` is a shortcut). A raw
`Color` in a screen is a defect.

Geist and Geist Mono are bundled under `assets/fonts` with their OFL license
(`assets/fonts/OFL.txt`).

The theme mode (system, light, dark) and the privacy mode are chosen in Mais
and held in `displayPreferencesProvider`.

## Rules from the brief

- Designed at 360dp first, touch targets at least 48dp, body text at least
  14sp, AA contrast in both themes.
- No state is told by color alone: `CdStatusBadge` always pairs the tone's
  icon with a label.
- Privacy mode hides every amount (`R$ ••••`), including signs, through
  `MoneyFormat.format(hide: true)`; `CdAmount` reads the preference itself.
- A minus sign is the true minus (U+2212), never a hyphen.

## Components

`lib/core/widgets/`, all prefixed `Cd`:

| Folder     | Components |
| ---------- | ---------- |
| `brand`    | `CdMark` |
| `buttons`  | `CdButton` (`filled`, `tonal`, `outlined`, `text`, `danger`; `dense`, `loading`, `expand`) |
| `charts`   | `CdLineChart`, `CdBarChart`, `CdDonut` |
| `feedback` | `CdStatusBadge`, `CdInlineBanner`, `showCdToast` and `showOutcomeToast`, `ToneIcon` |
| `inputs`   | `CdTextField`, `CdCurrencyInput`, `CdSearchField`, `CdSegmented`, `CdFilterChip`, `CdCheckboxRow` |
| `layout`   | `CdCard`, `CdListRow`, `CdSectionHeader`, `CdKeyValueRow`, `CdIconTile`, `CdEntityBadge`, `CdStepper`, `CdNavBar`, `showCdBottomSheet` |
| `money`    | `CdAmount`, `CdAccountCard`, `CdBillCard`, `CdBudgetBar`, `CdTransactionRow`, `CdCopyField`, `CdPaymentLadder`, `CdConfirmSheet`, `PrivacyToggle` |
| `states`   | `CdEmptyState`, `CdErrorState`, `CdSkeleton`, `CdStateView`, `ComingSoon` |

Feature widgets: `EntitySwitcher` and `EntityKindBadge` (`features/entities`),
`PaymentLadderView` (`features/bills`), and the three home layouts in
`features/home/presentation`.

## Screens without an endpoint

Rails, Open Finance by item id, capture sources, receipts, card statement
import, invoice issuer, payroll, transfers, accountant export and sign-up or
unlock read fake repositories with fictional data for both backends. Each
feature's providers file says so; swapping in an API adapter touches only
that provider.
