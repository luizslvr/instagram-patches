/*
 * Part of the Instagram patches fork:
 * https://github.com/luizslvr/instagram-patches
 *
 * Licensed under GPLv3. See the LICENSE file at the repository root.
 */

package app.morphe.patches.instagram.patches.distractionFree

import app.morphe.library.instagram.utility.JsonParserFingerprint
import app.morphe.library.instagram.utility.replaceJsonFieldWithBogus
import app.morphe.patcher.patch.BytecodePatchContext
import app.morphe.patcher.patch.booleanOption
import app.morphe.patcher.patch.bytecodePatch
import app.morphe.patches.Constants.COMPATIBILITY_INSTAGRAM

/**
 * JSON keys carrying the engagement numbers rendered under a post or reel.
 *
 * These are the field names Instagram's media objects use. They are NOT obfuscated: JSON keys are
 * part of the wire format and the server dictates them, so R8 cannot rename them.
 *
 * VERIFY BEFORE SHIPPING: run tools/dump_json_keys.sh against the target APK and delete any key
 * this build does not actually contain. A key that is absent is harmless (JsonParserFingerprint
 * simply matches nothing) but it hides the fact that the number is being served under a name you
 * have not covered. Better to know.
 */
private val POST_COUNT_KEYS = listOf(
    "like_count",
    "comment_count",
    "repost_count",
    "reshare_count",
    "share_count",
    "play_count",
    "view_count",
    "save_count",
)

/**
 * Profile header numbers.
 */
private val PROFILE_COUNT_KEYS = listOf(
    "follower_count",
    "following_count",
    "media_count",
)

/**
 * Replaces a parsed JSON key with a key the parser does not know.
 *
 * `ReplaceJsonFieldWithBogus` swaps the key literal for "BOGUS", so the field is never populated
 * and the number renders as nothing. Unknown keys are ignored by the parser, so there are no side
 * effects on the rest of the payload.
 *
 * Two paths, because the library offers both and they differ in whether they move the instruction
 * indices around:
 *
 *  - String match: the key is a literal in the method body, so `replaceInstruction` is used. It
 *    keeps the instruction count identical, which means indices found for *other* keys in the same
 *    method afterwards are still valid.
 *  - Dictionary match: the key is reached through the parser's switch discriminator, and the
 *    library inserts a `const/4` after it. That shifts everything below it, so each such match is
 *    applied on its own match record rather than re-scanned.
 */
internal fun BytecodePatchContext.bogusJsonKey(key: String) {
    JsonParserFingerprint(key).matchAll().forEach { match ->
        if (match.isStringMatch) {
            match.method.replaceJsonFieldWithBogus(key)
        } else {
            match.replaceJsonFieldWithBogus()
        }
    }
}

/**
 * Hides engagement numbers: the counts under posts and reels, and the profile header numbers.
 *
 * Nothing but the number is removed. The post still loads, the heart still renders, the comment
 * section still works unless Hide comments is also applied — what disappears is the tally. This is
 * the "stop keeping score" setting, deliberately additive with the other patches in this bundle
 * rather than a replacement for them.
 *
 * The unread message badge is a separate patch (Hide message badge) because it is read from the
 * inbox document, not from media payloads.
 */
@Suppress("unused")
val hideCountsPatch = bytecodePatch(
    name = "Hide counts",
    description = "Hides like, comment, share, save and view counts on posts and reels, and the " +
            "follower, following and post counts on profile pages.",
    default = true
) {
    compatibleWith(COMPATIBILITY_INSTAGRAM)

    val hidePostCounts by booleanOption(
        key = "hidePostCounts",
        default = true,
        title = "Hide post and reel counts",
        description = "Hides the like, comment, share, save and view counts shown on posts and reels."
    )

    val hideProfileCounts by booleanOption(
        key = "hideProfileCounts",
        default = true,
        title = "Hide profile counts",
        description = "Hides the follower, following and post counts on profile pages."
    )

    execute {
        if (hidePostCounts == true) POST_COUNT_KEYS.forEach { bogusJsonKey(it) }
        if (hideProfileCounts == true) PROFILE_COUNT_KEYS.forEach { bogusJsonKey(it) }
    }
}
