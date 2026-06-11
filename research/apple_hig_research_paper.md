# Applying Apple’s Human Interface Guidelines to a Native AI Assistant App

## Abstract

Apple’s Human Interface Guidelines should not be treated as a decoration manual. They are closer to a product quality system: a set of rules for making software feel native, readable, accessible, predictable, and respectful of the user. For a native AI assistant app such as Kodai, the HIG should guide every major design decision: app structure, sidebar behavior, typography, glass/material use, feedback, privacy, accessibility, generative AI behavior, and platform adaptation.

The central recommendation is simple: do not “make an Apple-looking app” by copying surface visuals. Build the app using Apple’s native patterns first, then apply visual personality carefully. The more Kodai uses system components, platform navigation, standard controls, system materials, accessibility-aware contrast, and clear feedback, the more it will feel like it belongs on macOS and iOS.

---

## 1. Why the HIG Matters

Apple’s HIG exists to help developers create experiences that feel appropriate on Apple platforms. That means the HIG is not only about beauty. It is about user trust, legibility, consistency, accessibility, and behavior. A user should not have to relearn basic interaction just because they opened your app.

For Kodai, this matters because the app is not a toy UI. It is intended to become a local-first assistant, project organizer, memory system, and development companion. That kind of app can become messy fast. The HIG gives you a stable design foundation before you add experimental AI features.

The key principle:

> Native first, custom second.

---

## 2. The HIG as a Design Operating System

You should refer to the HIG as a decision framework, not as a one-time reading assignment. Every feature should pass through a basic HIG filter:

1. What is the user trying to do?
2. What Apple platform pattern already exists for this?
3. Is this navigation, content, control, feedback, or status?
4. Can SwiftUI/AppKit provide the behavior natively?
5. Is the result readable, accessible, and predictable?
6. Does the custom styling improve the task, or is it just visual noise?

For Kodai, this means the HIG should become part of your project documentation.

Recommended documentation structure:

```text
Docs/
  Apple_HIG_Application.md
  Design_Decisions.md
  UI_Audit_Checklist.md
```

Each feature should include a short design record:

```text
Feature: Chat sidebar
User goal: Switch chats/projects quickly
Relevant HIG area: Sidebars, navigation, layout
Native pattern: NavigationSplitView / Sidebar
Implementation rule: Use sidebar for stable navigation, not random buttons
Acceptance test: User can identify current chat/project without explanation
```

This turns Apple’s guidance into actual engineering criteria.

---

## 3. Layout: Content Comes First

Apple’s guidance favors clear layout, readable content, proper alignment, and controls that stay close to the content they modify.

For Kodai, this should mean:

- The conversation is the main content.
- Sidebar items should support navigation, not compete with the chat.
- Metrics, memory, context, and tools should be visible but secondary.
- Avoid dense dashboards inside the main chat unless the user opens an inspector or detail panel.
- Do not hide basic actions behind flashy visuals.

A good Kodai macOS structure would be:

```text
Window
  Sidebar
    New Chat
    Chats
    Projects
    Files
    Memories
    Settings

  Main Content
    Active conversation
    Composer
    Response metadata

  Optional Inspector
    Context used
    Tool calls
    Memory summary
    Project notes
    Source/file references
```

The old-school Apple idea still holds: hierarchy first. Users should know where they are, what they can do, and what changed.

---

## 4. macOS: Respect the Desktop

A macOS app should feel like a Mac app, not a stretched iPhone app.

For Kodai, that means:

- Use a sidebar for persistent navigation.
- Use a toolbar for global actions.
- Support keyboard shortcuts.
- Support resizable windows.
- Support drag-and-drop files.
- Use context menus where appropriate.
- Keep high-density information available without overwhelming the main view.
- Prefer native macOS controls before inventing custom ones.

Kodai should use macOS strengths: sidebars, inspectors, menus, search fields, keyboard-first interaction, and multi-window or project-window thinking.

The Mac is a work machine. Treat it like one.

---

## 5. iOS: Same Product, Different Shape

If Kodai also exists on iOS, the app should not simply copy the macOS layout. The product identity can stay the same, but the structure should adapt.

macOS can use:

```text
Sidebar + Main Chat + Inspector
```

iOS should likely use:

```text
Tab / navigation stack + Chat + modal project/file views
```

The same concepts exist, but the interaction model changes. A phone screen cannot carry the same persistent information density as a Mac window.

The principle:

> Same app soul, different platform body.

---

## 6. Liquid Glass and Materials

Liquid Glass should not be used everywhere. Apple’s newer design direction treats glass as a functional layer for controls and navigation, not as a blanket texture over every object.

For Kodai, the rule should be:

> Glass belongs to navigation, controls, toolbars, sidebars, overlays, and floating status elements. The conversation content should remain readable and calm.

Good use:

```text
Glass sidebar
Glass toolbar
Glass floating context indicator
Glass command palette
Glass tool status pill
```

Bad use:

```text
Every message bubble is heavy glass
Glass on top of glass
Transparent text areas with poor contrast
Decorative blur that makes reading harder
Animated glass that distracts from writing
```

The best Apple-like design is usually restrained. Let the content breathe. Let glass support structure.

---

## 7. Typography and Readability

Typography should be boring in the best way. It should disappear because it works.

For Kodai:

- Use the system font.
- Use clear hierarchy: title, section label, message body, metadata.
- Avoid tiny token/stat text unless it is secondary and still legible.
- Keep code blocks monospaced.
- Keep assistant responses readable before making them pretty.
- Do not let translucent backgrounds reduce contrast.

A simple rule:

> If the user has to squint, the design failed.

---

## 8. Accessibility Is Not Optional

Apple treats accessibility as a core design requirement, not a bonus. Kodai should support accessibility from the beginning because AI apps are text-heavy and can easily become visually complex.

Kodai should account for:

- Increase Contrast
- Reduce Transparency
- Reduce Motion
- Dynamic Type where applicable
- VoiceOver labels
- Keyboard navigation
- Focus states
- Clear hit targets
- Readable color contrast

Liquid Glass especially needs fallback behavior. If transparency is reduced, the app should still look intentional. If motion is reduced, the app should still feel alive through layout and feedback, not constant animation.

---

## 9. Feedback: The App Must Show What It Is Doing

AI apps fail when the user cannot tell what is happening. Apple’s feedback guidance is directly relevant here: the interface should communicate status, success, failure, warning, and correction opportunities.

Kodai should show:

```text
Thinking
Generating
Using local model
Using larger/cloud model, if added later
Searching files
Reading project memory
Tool failed
Context near limit
Response saved
Memory updated
```

This does not mean noisy popups. It means quiet, visible state.

Example assistant response metadata:

```text
Local · 1.2s first token · 24 tok/s · Context 58% · 2 files referenced
```

This is useful because it makes the AI process observable. For your app vision, that matters a lot.

---

## 10. Generative AI: Be Clear, Editable, and Correctable

Apple’s newer guidance around generative AI is especially relevant for Kodai. AI output should not feel like a mysterious black box. The user should understand what happened and retain control.

Kodai should make AI behavior visible:

- What context was used?
- What files were referenced?
- Was this local or remote?
- Was memory updated?
- Can the user undo that memory update?
- Can the user refine the result?
- Can the user see tool actions?
- Can the user stop generation?

The practical rule:

> Every AI action should have state, source, and user control.

Example:

```text
Memory event:
Saved to Project/KodaiMac/project_summary.md
Reason: User discussed sidebar/project structure
Undo available
```

That fits the “glass box” idea: the app does not hide its process.

---

## 11. Privacy and Local-First Design

Apple’s privacy guidance emphasizes transparency about data and resources the app needs. This fits Kodai perfectly because local-first privacy is part of the product identity.

Kodai should make privacy visible:

```text
Local model active
No network used
Files stay on device
Memory stored locally
Cloud model disabled
```

If web search or cloud models are added later, do not bury that. Make routing obvious:

```text
This request needs web access.
Local model cannot browse.
Use web tool?
```

This is not just ethical. It is good product design. Users trust software that tells them what it is doing.

---

## 12. Icons and Visual Identity

Apple’s newer icon guidance emphasizes layered icons, platform consistency, light/dark/tint/clear appearances, and Liquid Glass behavior.

For Kodai, the logo should be simple enough to survive every mode.

A good Kodai icon should be:

- Recognizable at small sizes.
- Not overly detailed.
- Compatible with dark and light appearances.
- Built from a few clear layers.
- Futuristic, but not noisy.
- Consistent between macOS and iOS.

Do not make the icon look like generic AI vaporware. Strong shape, restrained depth, recognizable silhouette.

---

## 13. Practical Application Checklist for Kodai

### Structure

- Does this use a native Apple navigation pattern?
- Is the current location obvious?
- Are controls close to the content they modify?
- Is the sidebar stable and understandable?

### Visual Design

- Is the content readable before effects are added?
- Is glass used for navigation/control rather than content?
- Does the UI still work in dark mode, light mode, and high contrast?
- Are icons from SF Symbols where possible?

### AI Behavior

- Does the user know what the model is doing?
- Are tool calls visible?
- Are memory writes visible?
- Can the user undo or edit important AI-created data?
- Is local/cloud routing clear?

### Accessibility

- Is text legible?
- Is contrast strong enough?
- Does Reduce Motion still feel good?
- Does Reduce Transparency still look intentional?
- Can the app be used from keyboard?

### macOS Quality

- Are there keyboard shortcuts?
- Are menus/context menus used where they make sense?
- Is the window resizable?
- Does the toolbar feel native?
- Does the sidebar behave like a Mac sidebar?

---

## 14. Recommended Design Rule for Kodai

Use this as the main rule in your project prompt:

```text
Kodai should follow Apple Human Interface Guidelines by default:
native structure first, readable content first, system components first,
glass only where it supports hierarchy, transparent AI behavior always,
privacy visible, accessibility respected, and custom styling restrained.
```

That is stronger than saying “make it Apple-like.” It tells the model what to actually do.

---

## 15. Conclusion

Apple’s HIG should be used as a working design standard for Kodai. The goal is not to imitate Apple’s surface style. The goal is to build software that behaves like it belongs on Apple platforms.

For Kodai, the HIG points toward a clear product direction:

- Native macOS structure
- Calm readable chat
- Glass used as a functional layer
- Visible AI state
- Local-first privacy
- Strong accessibility
- Inspectable project and memory systems

The best version of Kodai should feel modern, but not gimmicky. It should feel personal, but not messy. It should feel intelligent, but not unpredictable. That is exactly where Apple’s design guidance is most useful.

---

## Source Notes

1. Apple Design  
   https://developer.apple.com/design/

2. Apple Human Interface Guidelines  
   https://developer.apple.com/design/human-interface-guidelines/

3. UI Design Dos and Don’ts  
   https://developer.apple.com/design/tips/

4. Accessibility — Human Interface Guidelines  
   https://developer.apple.com/design/human-interface-guidelines/accessibility

5. Feedback — Human Interface Guidelines  
   https://developer.apple.com/design/human-interface-guidelines/feedback

6. Privacy — Human Interface Guidelines  
   https://developer.apple.com/design/human-interface-guidelines/privacy

7. Apple Design — What’s New  
   https://developer.apple.com/design/whats-new/

8. WWDC Design Videos  
   https://developer.apple.com/videos/design/
