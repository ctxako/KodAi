# Kodai macOS 26 Design Doctrine

## Native Minimal Glass Assistant Built for Apple’s New Design System

### 1. North Star

Kodai should feel like it belongs on macOS 26 from the first launch. It should not look like a web chatbot pasted into a Mac window. It should feel native, calm, spatial, readable, keyboard-friendly, and deeply integrated with the system.

The app should be a minimal glass assistant, not a futuristic dashboard. The interface should support conversation, focus, and task flow without fighting the content. Glass should create structure and depth, not visual noise.

The core design phrase:

**Content first. Controls float. Glass is earned.**

---

# 2. Apple-Like Design Principles

## 2.1 Use system behavior before custom behavior

Default to SwiftUI/macOS-native components wherever possible:

* NavigationSplitView
* native toolbar
* native sidebar behavior
* native search field
* native menus
* native context menus
* native buttons
* native text editing
* native keyboard shortcuts
* native focus states
* native sheets/popovers/alerts

Only build custom UI when the system component cannot express the feature clearly.

Bad direction: custom neon panels, custom fake title bars, decorative glass cards everywhere.

Good direction: native window, native toolbar, focused sidebar, clean transcript, glass composer/control surface.

---

## 2.2 Glass is a hierarchy layer, not a wallpaper

Liquid Glass should mostly appear on:

* toolbar controls
* sidebar/navigation surfaces
* floating composer
* mode switcher
* compact action groups
* transient controls
* sheets/popovers/menus where appropriate

Liquid Glass should generally not be applied to:

* every chat bubble
* full transcript background
* message text containers
* code blocks
* every card/list row
* nested panels
* decorative blobs
* glass over glass

The chat transcript is content. The sidebar, toolbar, composer, and mode controls are interface.

---

## 2.3 Keep the app visually quiet

Kodai should not scream “AI.” It should feel like a serious Mac utility.

Use:

* restrained dark background
* soft cool-gray/blue atmosphere
* system text styles
* SF Symbols
* subtle spacing
* clean hierarchy
* one clear primary action

Avoid:

* too many gradients
* over-glowing borders
* random purple/blue effects
* heavy shadows
* large animated background blobs
* novelty sci-fi controls
* cluttered mode pickers

The app should feel premium because it is restrained.

---

# 3. Window Structure

## 3.1 Use a real Mac window

The app should preserve Mac expectations:

* draggable window area
* native traffic lights
* standard titlebar behavior
* native toolbar region where useful
* keyboard shortcuts
* menu bar commands
* resizable layout
* accessible focus order

Do not fake the entire chrome unless there is a strong reason. Apple-like apps respect the window.

---

## 3.2 Preferred layout

For a macOS 26 assistant, use this structure:

**Left:** glass/inset sidebar
**Center:** calm conversation/content canvas
**Bottom:** floating glass composer
**Top:** minimal toolbar/title/action area
**Optional right:** inspector only when needed later

The app should scale from compact to wide:

* compact: sidebar collapses
* medium: sidebar visible, chat centered
* wide: optional inspector/context pane can appear

---

# 4. Liquid Glass Rules

## 4.1 Use glass for the navigation/control layer

Glass should visually say:

“This is interactive system-level UI floating above your work.”

Use it for:

* sidebar container
* toolbar item groups
* send/action button group
* mode picker
* “new chat” control
* attachment/tools group
* voice/dictation button
* temporary suggestion pills

Do not use glass to say:

“This is just content.”

Chat messages should usually be flat, readable surfaces.

---

## 4.2 Avoid glass-on-glass

Never stack a glass card on top of a glass sidebar or glass background unless the top element is clearly part of the same grouped glass system.

If several glass controls sit close together, group them visually and technically as one glass relationship. They should feel like one liquid control cluster, not random floating bubbles.

---

## 4.3 Glass needs separation from content

If content scrolls underneath a glass toolbar/composer/sidebar, the app needs a clear edge treatment. Use scroll edge effects or equivalent system behavior so text never competes with translucent controls.

The user should never struggle to read a button because message text is moving underneath it.

---

## 4.4 Do not decorate what glass already explains

Remove old design tricks:

* extra borders around toolbar buttons
* fake frosted cards behind controls
* unnecessary divider lines
* extra background rectangles
* glowing outlines
* duplicated shadows

With macOS 26, hierarchy should come from:

* layout
* grouping
* tint prominence
* control placement
* spacing
* native material behavior

---

# 5. Shape Language

## 5.1 Use Apple’s shape rhythm

The UI should use three shape families:

* rounded rectangles for dense Mac controls
* capsules for prominent actions
* concentric rounded shapes for nested containers

Small/medium desktop controls should stay compact and rectangular. Large primary controls can become capsule-like.

---

## 5.2 Maintain concentricity

Nested rounded shapes should feel mathematically related.

Example:

* window corner radius
* sidebar glass corner radius
* inner button radius
* composer radius
* text input radius

They should visually nest. Corners should not look pinched, random, or mismatched.

---

# 6. Typography

Use system typography. Do not create a custom “AI brand font” unless absolutely necessary.

Recommended hierarchy:

* App title: system rounded or default system, semibold
* Sidebar labels: standard callout/body
* Message text: readable body size
* Metadata/status: caption or footnote
* Code: monospaced system font
* Buttons: system label styles

Text should be left-aligned in serious UI areas. Avoid centered text except for empty states or onboarding moments.

---

# 7. Color

## 7.1 Use semantic/system color first

Use system colors for:

* primary text
* secondary text
* disabled text
* selection
* accent
* backgrounds
* dividers where needed

Custom colors should be atmospheric, not structural.

---

## 7.2 Suggested Kodai palette direction

Base mood:

* deep blue-gray
* graphite
* muted steel blue
* desaturated teal-gray
* very subtle purple only as atmosphere

Avoid bright neon as a core UI color.

The app should feel like a quiet Apple utility with a slight personal aura, not a gaming overlay.

---

## 7.3 Accent color

Use one primary accent. Let macOS accent behavior carry interaction states where possible.

Good accent use:

* send button
* active mode
* selected sidebar item
* important status
* progress/streaming indicator

Bad accent use:

* every card
* every icon
* background glow
* every message bubble

---

# 8. Sidebar

## 8.1 Sidebar role

The sidebar is navigation, not decoration.

It should contain:

* New Chat
* Conversations
* Modes or Spaces
* Search
* Settings
* maybe pinned projects later

It should not become a giant dashboard.

---

## 8.2 Sidebar behavior

Sidebar should:

* feel inset/floating
* use Liquid Glass or native sidebar material
* support collapse
* keep selected item obvious
* use SF Symbols
* use short labels
* group items clearly

Avoid:

* oversized custom menu tiles
* too many top-level modes
* cramped labels
* random icon styles
* large title/subtitle stacks pushing content down awkwardly

---

# 9. Toolbar and Menu Bar

## 9.1 Toolbar

The toolbar should contain only frequent, window-level actions.

Good toolbar items:

* sidebar toggle
* new chat
* search
* model/status indicator
* settings
* inspector toggle later

Do not overload the toolbar with every possible AI command.

Group related toolbar actions together. Keep the primary action visually separate if it needs emphasis.

---

## 9.2 Menu bar

A real Mac app should have real menu commands.

Include menu commands for:

* New Chat
* Open Conversation
* Search
* Copy
* Export
* Clear Chat
* Settings
* Help
* Toggle Sidebar
* Toggle Inspector later
* Focus Composer
* Send Message
* Stop Generation

Unavailable commands should remain visible but disabled where appropriate, so the user can discover the app’s capabilities.

---

# 10. Chat Transcript

## 10.1 Transcript is content

The transcript should prioritize reading.

Message design:

* simple spacing
* no heavy bubble obsession
* assistant messages can be plain content blocks
* user messages can be subtly grouped or aligned
* code blocks must be readable
* markdown should render cleanly
* timestamps/status should be quiet

Do not make every message glass.

---

## 10.2 Assistant message quality

Each assistant message should support:

* markdown
* code blocks
* copy button
* optional regenerate
* optional collapse/expand for long outputs
* source/context display later
* streaming status
* completion state

Keep message actions hidden or subtle until hover, so the transcript stays clean.

---

# 11. Composer

## 11.1 Composer as primary glass control

The composer is one of the few places where custom glass makes sense.

It should feel like a floating control surface attached to the bottom of the content area.

Composer should include:

* text input
* send button
* stop button while generating
* attachment/context button
* tools button later
* optional mic/dictation button
* small model/status indicator

The composer should be calm, rounded, and highly readable.

---

## 11.2 Composer behavior

Composer must support:

* Return to send
* Shift-Return for newline
* Command-Return optional send
* Escape to stop/blur
* paste
* drag/drop files later
* input height expansion
* disabled state while needed
* clear streaming state

The send button should be visually primary but not huge.

---

# 12. AI Interaction Design

## 12.1 Be honest about the model

Kodai uses an on-device Apple Intelligence/Foundation Models style system. The app should not pretend the local model is an unlimited cloud model.

The UI should quietly communicate:

* local/on-device
* private by default
* works offline where supported
* best at summarizing, organizing, rewriting, extracting, classifying, and short assistant tasks
* may be weaker at fresh facts, deep coding, complex reasoning, or current events unless tools/context are provided

Do not overpromise.

---

## 12.2 Streaming is part of the experience

Streaming should feel responsive but stable.

Show:

* subtle “Generating” state
* stop button
* maybe tokens/sec or elapsed time only in developer/debug mode
* partial response smoothly updating
* no jumpy layout
* no fake “thinking” spam

For a polished Apple-like app, the default user-facing state should be simple:

“Generating…”

Advanced telemetry can live in a debug/status area, not the main chat surface.

---

## 12.3 Tool use needs trust

When Kodai eventually performs actions, use clear permission boundaries.

For low-risk actions:

* summarize
* organize
* draft
* classify
* rename local notes
* search local context

For higher-risk actions:

* sending messages
* editing files
* deleting data
* running commands
* modifying code
* committing to Git

Require review/confirmation.

The assistant should feel helpful, not sneaky.

---

# 13. Foundation Models Feature Fit

Best first features for an on-device assistant:

* summarize conversation
* rewrite text
* extract tasks
* classify notes
* generate titles
* organize ideas
* produce structured summaries
* convert rough thoughts into plans
* short Q&A over provided context
* generate UI copy
* generate small Swift snippets with review

Avoid making the first version depend on:

* broad world knowledge
* current facts
* advanced reasoning
* long codebase-wide edits
* autonomous agent behavior
* hidden background actions

Start with reliable local intelligence. Expand later through tools and explicit context.

---

# 14. Safety and Error Handling

Kodai should gracefully handle:

* model unavailable
* Apple Intelligence not enabled
* unsupported device/account/language
* guardrail refusal
* empty prompt
* long prompt
* tool failure
* file access failure
* interrupted generation
* app relaunch during session

Do not show raw technical failure unless in debug mode.

Good user-facing language:

* “I can’t complete that with the local model.”
* “Try narrowing the request or adding context.”
* “This action needs review before I run it.”
* “The model stopped because the request was blocked by safety rules.”

---

# 15. Accessibility

Accessibility is not optional.

Support:

* Reduce Transparency
* Increase Contrast
* Reduce Motion
* VoiceOver labels
* keyboard navigation
* focus rings
* readable contrast
* Dynamic Type where relevant
* clear button labels
* distinguishable selected states
* no meaning conveyed by color alone

Liquid Glass must remain legible when system accessibility settings change.

Never rely on blur/transparency as the only separator.

---

# 16. Motion

Motion should be subtle and purposeful.

Good motion:

* sidebar collapse/expand
* composer focus lift
* send button state change
* streaming response fade-in
* glass controls morphing when system provides it
* sheets emerging from their source control

Bad motion:

* constant background animation
* bouncing panels
* excessive shimmer
* animated blobs behind text
* distracting typing effects
* fake AI “thinking” theatrics

Motion should support continuity, not show off.

---

# 17. Icons

Use SF Symbols first.

Icon rules:

* consistent symbol weight
* consistent filled/outlined style
* use recognizable symbols
* add labels where icons are ambiguous
* keep menu icons aligned
* do not mix custom icon packs
* avoid overly detailed icons in toolbars

For the app icon, use the new layered Liquid Glass icon direction:

* simple silhouette
* strong central shape
* works in light/dark/tinted/clear appearances
* rounded/concentric geometry
* not too many tiny details
* no thin fragile lines

Kodai’s icon should feel like a native Mac app icon first, AI brand second.

---

# 18. Empty States

Empty states should be useful, not gimmicky.

Main empty chat state:

* app name
* one short sentence explaining what Kodai does
* 3–5 suggested starter prompts
* maybe local/private indicator
* no huge mascot
* no giant marketing paragraph

Example:

“Kodai helps you think, organize, and build locally on your Mac.”

Starter prompts:

* “Summarize this idea”
* “Turn this into a plan”
* “Help me debug SwiftUI”
* “Organize my project notes”
* “Draft a GitHub README”

---

# 19. Settings

Settings should be a native macOS Settings scene if possible.

Sections:

* General
* Appearance
* Model
* Memory/Context
* Privacy
* Developer
* Shortcuts
* Advanced

Avoid putting too many settings in the main sidebar.

---

# 20. Privacy Design

Because Kodai is local/on-device focused, privacy should be visible but not loud.

Include:

* clear local processing indicator
* explain what is stored
* allow clearing conversations
* allow clearing summaries/memory
* allow exporting data
* do not hide file access behavior
* do not silently send data elsewhere

If a future cloud model is added, it must be visibly different from local mode.

---

# 21. Performance Feel

A native Apple-like app must feel instant.

Targets:

* app launches quickly
* typing never lags
* scrolling transcript stays smooth
* sidebar animation is stable
* response streaming begins quickly when possible
* long chats do not destroy performance
* markdown/code rendering remains smooth
* memory summaries prevent huge context overload

A pretty app that lags is not Apple-like.

---

# 22. Rebuild Acceptance Checklist

Kodai is ready visually if:

* It looks native before it looks custom
* It uses system components wherever possible
* The chat transcript is readable and calm
* Glass appears mostly on controls/navigation
* There is no glass-on-glass clutter
* The sidebar feels like macOS 26, not a custom web drawer
* The composer feels like a floating control surface
* Toolbar actions are grouped and minimal
* Menu bar commands exist
* Keyboard shortcuts work
* Accessibility settings do not break the design
* Reduce Transparency still looks good
* Increase Contrast still looks good
* Reduce Motion still feels complete
* The AI states are clear: idle, generating, stopped, error
* The app does not overpromise the local model
* The app feels useful with only local/on-device features
* The icon follows the new layered/glass direction
* The whole UI feels quiet, premium, and intentional

---

# 23. Hard No List

Do not build:

* full-window fake glass blur everywhere
* neon sci-fi cockpit UI
* dashboard clutter
* glass chat bubbles stacked on glass panels
* oversized mode buttons
* fake native controls
* unreadable translucent text
* random gradients behind paragraphs
* hidden destructive AI actions
* cloud-AI claims for a local model
* toolbar packed with ten buttons
* settings inside the main chat view
* custom menus when native menus work
* motion that distracts from reading

---

# 24. Final Design Direction

Kodai should feel like a native macOS 26 assistant that happens to use AI, not an AI website trapped in a Mac window.

The visual system should be:

* native
* minimal
* glass-aware
* content-first
* keyboard-friendly
* private/local by default
* restrained
* expandable later into developer workflows

The best version of Kodai is not the flashiest version. It is the version that feels like Apple could have shipped it as a quiet local assistant for thinking, organizing, and building.

[1]: https://developer.apple.com/videos/play/wwdc2025/219/ "Meet Liquid Glass - WWDC25 - Videos - Apple Developer"
[2]: https://developer.apple.com/videos/play/wwdc2025/310/ "Build an AppKit app with the new design - WWDC25 - Videos - Apple Developer"
[3]: https://developer.apple.com/videos/play/wwdc2025/286/ "Meet the Foundation Models framework - WWDC25 - Videos - Apple Developer"
