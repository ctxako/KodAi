# App Store Submission Package

Everything App Store Connect asks for, pre-written. Update the bracketed
items before submitting. See PRODUCTION_PLAN.md Milestone 7 for exit criteria.

## Identity

- **Name**: kodai — private on-device assistant
- **Subtitle** (30 chars): Your AI. Entirely on-device.
- **Category**: Productivity
- **Age rating**: 4+
- **Price**: Free, no IAP

## Promotional text (170 chars)

An assistant that lives on your iPhone, not in the cloud. Set reminders,
manage your calendar, save files — by just asking. No account. No tracking.

## Description

kodai is a private assistant that runs entirely on your iPhone.

Type what you want done — "remind me to call mom tomorrow at 9", "what's on
my calendar Friday?", "save this to a file" — and kodai does it, showing you
exactly what it's about to change before it changes anything.

WHAT MAKES IT DIFFERENT

• Entirely on-device. The AI model lives on your phone. Your requests, your
  calendar, your reminders, your files — nothing is sent anywhere. Ever.
• No account. No sign-up, no login, no email. Install and use.
• No tracking. Zero analytics, zero telemetry, zero third-party SDKs.
• Works offline. Airplane mode changes nothing.
• You stay in control. Anything that writes — an event, a reminder, a file —
  shows a confirmation card first. Nothing happens without your OK.

WHAT IT CAN DO

• Calendar — create, check, and remove events
• Reminders — create to-dos and list items, check what's pending
• Contacts — find and add contacts
• Files — save, read, and organize notes in the app's iCloud Drive folder
• Clipboard — read and copy text
• Notifications — schedule one-off alerts
• Web — fetch a page's text, open links

Everything appears as action cards in a feed — what was asked, what was
done, when. The Upcoming tab shows what's ahead; the Archive keeps the
history. Siri and Shortcuts can trigger the same actions.

kodai runs a compact open language model (LFM 2.5) through llama.cpp,
optimized for iPhone. It's an agent, not a chatbot: it plans, uses tools,
and shows its work.

## Keywords (100 chars)

assistant,offline,private,on-device,AI,reminders,calendar,agent,no tracking,siri,local,llm

## App Review notes

- The app uses an on-device ML model (LFM 2.5 1.2B, GGUF format, run via
  llama.cpp) for natural-language understanding. There is NO server-side AI
  and no account system.
- [REVIEW BUILD] The model is bundled in the binary, so the app works
  immediately, fully offline. [If the submitted build downloads instead:
  first launch fetches the ~700 MB model from HuggingFace over HTTPS with
  progress UI; everything after that is offline.]
- Network use: the only network calls are (1) the optional one-time model
  download and (2) the user-invoked "fetch a web page" action. There are no
  analytics or telemetry calls of any kind.
- Permissions are requested per-domain with usage descriptions (calendar,
  reminders, contacts, notifications). The app is fully functional with all
  permissions denied — the assistant explains what it can't do and why.
- Every write action (create event, create reminder, save file, etc.) shows
  a confirmation card the user must accept before anything executes.
- To test: grant calendar + reminders in onboarding, then try
  "remind me to call mom tomorrow at 9am" and
  "what's on my calendar this week".

## Privacy questionnaire (App Store Connect)

- Data collection: **No data collected.** (No analytics, no identifiers, no
  user content leaves the device.)
- Tracking: none.
- Third-party SDKs: none (llama.cpp is compiled in; it makes no network calls).

## Screenshot shot list (6.7" + 6.1")

1. Feed with action cards — a created event + a reminder, statuses visible.
   Caption: "Ask. Confirm. Done."
2. Confirm card mid-flight. Caption: "Nothing happens without your OK."
3. Upcoming tab with grouped timeline. Caption: "Everything ahead, one place."
4. Onboarding privacy screen. Caption: "No cloud. No account. No tracking."
5. Model download / brain screen (or splash). Caption: "The AI lives on
   your iPhone."
6. Siri/Shortcuts invocation. Caption: "Works with Siri and Shortcuts."

## Rejection contingencies (pre-written answers)

- **"App is a thin wrapper over an LLM"** → It is a device-action agent with
  20 native tool integrations (EventKit, Contacts, Files, notifications),
  action cards, timeline, and Siri surface — the model is the parser, not
  the product.
- **"Model download too large"** → review build bundles the model; production
  download shows size upfront, requires confirmation, checks disk space, and
  resumes.
- **"Minimal functionality without permissions"** → the agent responds
  gracefully with zero permissions and explains how to enable each domain;
  onboarding is skippable by design.

## Checklist before submit

- [ ] 1024×1024 icon (pawprint vs. wolf constellation — pick one)
- [ ] Privacy policy URL live (see PRIVACY.md; host on ctxa.llc)
- [ ] Screenshots captured on-device (6.7" + 6.1")
- [ ] Version/build bumped; archive uses the BUNDLED-model configuration
- [ ] Entitlements: iCloud CloudDocuments container provisioned on the team
- [ ] TestFlight bake ≥2 weeks, no unresolved crash clusters
