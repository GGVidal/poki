# Result cards: design reference

Reference for designing result cards for more apps. The first card (Railway 12306 train list) is merged; this folder shows how it looks and behaves. Screenshots are from the iOS simulator. The 12306 app icon is blurred on purpose.

| File | What it shows |
|---|---|
| `01-train-card-recommended-selected.png` | The card under the task card. Poki's recommended train is selected. Primary button, one blue text button, then one sentence of conclusion. |
| `02-train-card-another-item-selected.png` | Another train tapped. Only the selection mark moves. Button labels and sentences follow the selected item. |
| `03-button-sends-a-sentence-then-asks-recipient.png` | A button tap becomes a normal user message in the chat. With no recipient in memory, Poki asks who to send it to. |

## Behavior shared by every card

- One state only: the selected item, defaulting to Poki's recommendation. It is saved with the conversation, so reopening the chat keeps it and old cards stay tappable.
- One primary button per card. At most one next step, as a native blue text button. No next step means no second button.
- A button tap is the same as the user typing one sentence. After that the normal flow handles progress, approvals and the Live Activity. The card never shows "sending" or "sent".
- Buttons are disabled while a task is running.
- A card appears only when there are two or more items to choose between. A single result is one sentence of text plus one native button (for example "View in Taobao"), with no card. This single-result form is not built yet.
- No promo badges, no deep-link capsule in the corner, no payment actions, no features Poki cannot do yet (such as price alerts). Never offer paying, booking or choosing seats.
- A fact that affects the choice goes in small grey text under the item, not in a coloured tag.
- If the card data is malformed, has fewer than two items or names an unknown kind, only the card is dropped and the full result is given as text.
- Anything the other app already shows live (a driver's position, for example) gets no card.

## Look per app

The shared behavior above is the same for all apps. The look is per app: rebuilt from real screenshots of that app on a test phone (type sizes, brand colour, list style), so the card feels like it ships with the app. A card that mixes several apps (price comparison) uses a native iOS shell with each row carrying its app's icon and colour. Native SwiftUI controls only.

## Card interface (merged in PR 486)

`finish_task` takes an optional `card`:

```json
{
  "app": "12306",
  "kind": "12306.trains",
  "items": [
    { "id": "G3", "title": "G3", "date": "11月19日 周四", "from": "北京南", "to": "上海虹桥",
      "depart": "08:00", "arrive": "12:32", "duration": "4小时32分", "price": "¥626",
      "seats": [{ "name": "二等座", "left": "有" }] }
  ],
  "recommended": "G3",
  "primary": { "label": "在 12306 查看", "say": "在 12306 打开 {date} {title} 次（{from} {depart} 开）" },
  "next":    { "label": "发送车次", "say": "把这趟车发出去：{date} {title} 次，{from} {depart} 开，{to} {arrive} 到，{price}" }
}
```

- Every item needs `id` and `title`. All other fields belong to the app's look and are kept as the model sent them.
- In `label` and `say`, `{field}` becomes that field of the selected item. `say` must contain at least one `{field}`, so it follows the selection.
- A new look is one SwiftUI view plus one entry in `ResultCardLooks.all`; the entry also holds a `problem` check (returns why items cannot be drawn), the app's tint and the main button's shape.

Files, all under `native/ios-app/Poki/Chat/`:

- `ResultCard/ResultCard.swift`: the card model, `ResultCardLook` and `ResultCardLooks`
- `ResultCard/ResultCardView.swift`: the shared card shell and buttons
- `ResultCard/RailwayTrains.swift`: the 12306 look, a good template to copy
- `Harness/Harness.swift`: the `finish_task` schema and the instructions the model reads (`resultCard`, `cardDescription`)
- `ChatModel.swift`, `ChatView.swift`: selection storage and the busy state
- `PokiTests/ChatHarnessTests.swift`: `testAResultCardTheAppCannotDrawLeavesTheWholeResultToTheReply`
