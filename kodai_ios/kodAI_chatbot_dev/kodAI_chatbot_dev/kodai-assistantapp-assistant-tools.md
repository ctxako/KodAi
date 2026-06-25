# kodAI — Tool List

**Legend:** `(local)` stays on-device · `(net)` needs network · `(perm)` needs a permission prompt

---

## READ — no confirm, just fetch & show

- `get_time` / `get_date` — (local)
- `get_weather(city)` — (net) WeatherKit/API
- `get_calendar(start, end)` — what's on the schedule — (perm) EventKit
- `list_reminders` / `search_notes(query)` — (perm)
- `search_docs(query)` — RAG over your own content, i.e. the MemoRx drug DB — (local)
- `calculate(expression)` — (local)

---

## WRITE — confirm card every time, model proposes → user accepts

- `add_to_list(list, item)` — shopping/grocery — (local)
- `log_health(metric, value)` — log water, weight, etc. — (perm) HealthKit
- `create_location_reminder(title, place)` — "remind me when I get home" — (perm) location
