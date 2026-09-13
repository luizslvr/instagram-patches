/*
 * Part of the Instagram patches fork:
 * https://github.com/luizslvr/instagram-patches
 *
 * Licensed under GPLv3. See the LICENSE file at the repository root.
 */

package app.morphe.patches.instagram.patches.distractionFree

import app.morphe.patcher.patch.bytecodePatch
import app.morphe.patches.Constants.COMPATIBILITY_INSTAGRAM

/**
 * The numbers that put a red bubble on the Direct icon in the navigation bar.
 *
 * Where they come from: the inbox document, not a media payload. `/api/v1/direct_v2/inbox/`
 * answers with an `inbox` object carrying the aggregate unread count, plus a per-thread count for
 * every conversation; the badge on the navigation bar is the aggregate, and the per-thread number
 * is what shows beside each row in the list.
 *
 * How this hides it: the same JSON-key technique Hide counts uses — the count fields are renamed
 * to a key the parser does not know, so the numbers are never populated and there is nothing to
 * render into a badge. The conversations themselves are untouched; blocking a field is not the same
 * as blocking the endpoint, and this patch does not touch the message list or the message endpoints.
 *
 * VERIFY BEFORE SHIPPING. This is the least certain lever in the bundle. Two reasons:
 *
 *  1. The field names drift more here than in the media payload. Run
 *       bash tools/dump_json_keys.sh Instagram.apk unseen
 *     to see how this build actually spells them, and adjust the list below.
 *
 *  2. The badge is also refreshed from realtime pushes in some builds, not only from the inbox
 *     response. If the badge survives this patch, the count is arriving on a push rather than being
 *     read from this document, and the fix is to fingerprint the badge setter instead. That cannot
 *     be located without the target APK; once it is available, `tools/verify_anchors.py` is the
 *     place to record the anchor, and this file is where the second lever would go.
 */
private val UNREAD_BADGE_KEYS = listOf(
    // Inbox-level aggregate, this is the number in the bubble.
    "unseen_count",
    "unread_count",
    // Message requests, which also raise the badge.
    "pending_requests_total",
)

@Suppress("unused")
val hideMessageBadgePatch = bytecodePatch(
    name = "Hide message badge",
    description = "Hides the unread message count bubble on the Direct icon in the navigation bar.",
    default = true
) {
    compatibleWith(COMPATIBILITY_INSTAGRAM)

    execute {
        UNREAD_BADGE_KEYS.forEach { bogusJsonKey(it) }
    }
}
