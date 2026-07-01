# kodai Privacy Policy

*Effective: [DATE]. Host this page at https://ctxa.llc/kodai/privacy (or
similar) and link it in App Store Connect.*

kodai is built so that there is nothing to have a privacy policy about.

## What we collect

Nothing.

kodai has no account system, no analytics, no telemetry, no crash-reporting
SDK, no advertising identifiers, and no third-party SDKs. We cannot see what
you ask it, what it does for you, or that you use it at all.

## Where your data lives

On your iPhone. The AI model that powers kodai runs entirely on your device
through llama.cpp. Your requests are processed locally and never transmitted.
The events, reminders, contacts, files, and notifications kodai manages are
stored by iOS in your own calendar, reminders, contacts, and files — exactly
as if you had created them by hand.

## Network access

kodai makes network requests in exactly two cases, both visible to you:

1. **One-time model download** (download builds only): on first launch, the
   app fetches its AI model file from HuggingFace over HTTPS, with your
   confirmation and a progress bar. The download contains no information
   about you.
2. **"Fetch a web page" actions**: if you ask kodai to fetch a URL, it
   requests that URL — like a browser would — and shows you the text. kodai
   never fetches anything you didn't ask for.

Everything else works fully offline.

## Permissions

kodai asks for access to Calendar, Reminders, Contacts, and Notifications
only to perform the actions you request, with iOS's standard permission
prompts. You can deny or revoke any of them in Settings; kodai keeps working
and simply tells you which actions are unavailable.

## Changes

If a future version ever changes any of the above, this page and the App
Store privacy label will be updated first, and the change will be called out
in the release notes.

## Contact

15ctxa@gmail.com
