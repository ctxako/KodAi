//
//  SamplerPlayground.swift
//  kodAI_chatbot_dev
//
//  Plain-language helper notes (`KnobInfo`) shown behind each ⓘ button in the
//  tuning card. The `SamplerKnobs` value type lives in KodaiKernel.
//

import Foundation
import KodaiKernel

extension SamplerKnobs {
    static let `default` = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
}

// MARK: - Knob explanations

/// One "ⓘ" explainer: a plain-language, beginner-friendly description of what a
/// knob does and an experiment to try, shown in a small sheet when the user taps
/// the info button next to it. Written to teach, not just to define.
struct KnobInfo: Identifiable {
    let id = UUID()
    let title: String
    let body: String

    static let temperature = KnobInfo(
        title: "Temperature",
        body: """
        The big creativity dial. The model scores every possible next word; \
        temperature decides how much it favors its top pick over the long shots.

        • Low (0.2): almost always the safest word. Focused and consistent, but \
        can get repetitive or boring.
        • High (1.3+): gives unlikely words a real chance. Surprising and creative, \
        but can wander or go off the rails.
        • At the floor it's nearly deterministic — basically always the top word.

        Rule of thumb: lower for facts, code, and structured answers; higher for \
        brainstorming, stories, and play.

        Try this: ask the same question twice at 0.2, then twice at 1.2. Notice how \
        the low-temp answers look almost identical and the high-temp ones vary.
        """
    )

    static let topP = KnobInfo(
        title: "Top-P (nucleus)",
        body: """
        A smart shortlist. The model lines its options up best-first and keeps \
        adding them until their combined probability reaches P — then ignores the \
        rest. It adapts: few options when the model is confident, many when it's \
        unsure.

        • 1.0 = keep everything (off).
        • 0.9 = keep the most likely options that together cover 90% of the odds.
        • Low (0.5) = only the very top, safest options survive.

        Most people leave temperature moderate and tune top-P to trim the weird \
        tail without killing variety.

        Try this: set temperature to 1.2 (chaotic), then pull top-P down to 0.8. \
        The output stays varied but stops producing nonsense words.
        """
    )

    static let topK = KnobInfo(
        title: "Top-K",
        body: """
        A blunt cap on the shortlist: keep only the K highest-scoring words, throw \
        everything else away, then choose among the survivors.

        • K = 1 is greedy decoding — always the single best word (see \
        Deterministic).
        • K = 40 (default) lets a healthy field compete.
        • Large K barely restricts anything.

        Unlike Top-P, it ignores *how* confident the model is — it just counts. \
        Top-K and Top-P are often used together: K sets a hard ceiling, P trims \
        adaptively underneath it.

        Try this: drop K to 2 — the model gets very predictable, because it's only \
        ever choosing between its two favorite words.
        """
    )

    static let repeatPenalty = KnobInfo(
        title: "Repeat penalty",
        body: """
        Discourages the model from reusing words it has already said, to stop \
        loops like "the the the" or one phrase repeating.

        • 1.0 = off.
        • 1.05–1.15 = gentle, usually enough.
        • 1.5+ = aggressive; can start to distort wording or grammar.

        It looks back over recent tokens and lowers the score of ones already used. \
        For finer control, see Frequency and Presence penalties in Advanced.

        Try this: if a reply ever gets stuck repeating itself, nudge this up by \
        0.05 at a time until it breaks the loop.
        """
    )

    // MARK: Advanced

    static let minP = KnobInfo(
        title: "Min-P",
        body: """
        A modern, quality-first filter. It throws out any word whose probability \
        is below a fraction of the single best word's probability.

        • 0.0 = off.
        • 0.05 = keep only words at least 5% as likely as the top pick.
        • Higher = stricter, fewer survivors.

        Why people like it: it scales with the model's confidence automatically. \
        When the model is sure, it keeps almost nothing else; when it's torn, it \
        keeps more. Many find Min-P alone gives better results than Top-P + Top-K.

        Try this: turn Top-P and Top-K off-ish (1.0 and high), set Min-P to 0.05, \
        and raise temperature to 1.3. You get creativity without gibberish.
        """
    )

    static let frequencyPenalty = KnobInfo(
        title: "Frequency penalty",
        body: """
        Repetition control that *grows* with overuse: the more times a word has \
        already appeared, the harder it gets pushed down next time.

        • 0.0 = off.
        • 0.1–0.5 = trims compulsive repetition while staying natural.
        • High = the model actively avoids any word it has used, which can read as \
        strained "thesaurus mode."

        Pairs with Presence penalty: frequency scales with count, presence is a \
        one-time hit. This is the same idea as OpenAI's frequency_penalty.

        Try this: on a long answer that keeps hammering one term, raise this to ~0.3 \
        and watch the vocabulary spread out.
        """
    )

    static let presencePenalty = KnobInfo(
        title: "Presence penalty",
        body: """
        Encourages new topics. As soon as a word has appeared even once, it takes \
        a flat penalty — no matter how many times it shows up after.

        • 0.0 = off.
        • 0.1–0.6 = nudges the model toward fresh words and ideas.
        • High = strong push to keep introducing something new.

        Think of it as "reward novelty." Frequency penalty fights *repetition*; \
        presence penalty fights *staying on the same subject*. Same idea as \
        OpenAI's presence_penalty.

        Try this: for a brainstorm, set presence to ~0.5 — the model keeps branching \
        into new directions instead of circling one.
        """
    )

    static let deterministic = KnobInfo(
        title: "Deterministic (greedy)",
        body: """
        Turns off all randomness. The model always takes its single highest-scoring \
        word, every time — this is called greedy decoding.

        • Same prompt → same answer, word for word.
        • Temperature, Top-K, Top-P, and Min-P stop mattering (there's no sampling \
        to shape).
        • Output is the most "expected" continuation: reliable, sometimes flat.

        Great for: debugging, comparing prompts fairly, or when you want the model's \
        single most-confident answer.

        Try this: turn this on and resend the same message a few times — identical \
        replies. Turn it off and the answers start to vary again.
        """
    )

    static let seed = KnobInfo(
        title: "Seed (reproducibility)",
        body: """
        Randomness needs a starting number — the seed. Normally it's different every \
        time, so you get fresh answers. Lock it and the "random" choices repeat.

        • Unlocked = a new seed each generation (normal, varied).
        • Locked = the same seed reused, so a given prompt + tuning tends to \
        reproduce the same reply.

        This is a core research/learning tool: lock the seed, change ONE knob, and \
        any difference you see is caused by that knob — not luck.

        Note: reproducibility is best-effort here. Because the chat keeps the model \
        "warm" between turns, a brand-new chat is the most reliable way to see an \
        identical run. Tap Reroll to jump to a different fixed seed.
        """
    )

    static let maxLength = KnobInfo(
        title: "Max response length",
        body: """
        A hard ceiling on how many tokens (roughly word-pieces) the model may \
        produce in one reply. It does not change *what* the model says, only how \
        long it's allowed to run before being cut off.

        • Lower = snappier, cheaper, faster replies; may cut off mid-thought.
        • Higher = room for long, detailed answers; slower and uses more of the \
        context window.

        A token is about ¾ of a word on average, so 384 tokens ≈ 280–300 words.

        Try this: set it low (~96) for quick back-and-forth, then high for an essay \
        or a long code block, and feel the difference in speed.
        """
    )
}
