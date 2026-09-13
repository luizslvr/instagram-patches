/*
 * Part of the Instagram patches fork:
 * https://github.com/luizslvr/instagram-patches
 *
 * Licensed under GPLv3. See the LICENSE file at the repository root.
 */

package app.morphe.patches.instagram.patches.distractionFree

import app.morphe.library.instagram.patches.blockUrl
import app.morphe.library.instagram.patches.blockUrlBasePatch
import app.morphe.patcher.patch.bytecodePatch
import app.morphe.patches.Constants.COMPATIBILITY_INSTAGRAM

/**
 * Removes the ability to view comments on posts and reels.
 *
 * Implemented at the network layer rather than in the UI, because comments are rendered from a
 * server payload. The comment section is fed by a handful of endpoints under
 * `/api/v1/media/{media_id}/`:
 *
 *   - `/comments/`      fetches the comment list and its pagination pages.
 *   - `/comment/`       posts a new comment (also used by the inline reply box).
 *   - `/comment_likes/` comment like lists.
 *
 * `BlockUrlRequestPatch` hooks `TigonServiceLayer.startRequest` and throws an IOException for any
 * URI containing one of the configured substrings, so the request never leaves the device. With
 * the payload never arriving, Instagram has nothing to draw: the "View all N comments" row and
 * the comment sheet stay empty, and the comment action fails, which is the effect we want.
 *
 * NOTE: these substrings are matched with `String.contains` against the full URI, so the match is
 * deliberately kept to the path segment (`/comments/`, not `comments`) to avoid catching unrelated
 * endpoints whose name merely contains the word.
 *
 * VERIFY BEFORE SHIPPING: confirm each substring against the actual target APK with
 *   tools/dump_network_endpoints.sh
 * Instagram has moved comment reads between `/comments/` and the newer GraphQL
 * `comment_list_...` documents across releases. On a version where comments are served by
 * GraphQL, add the document name to the list below.
 */
@Suppress("unused")
val hideCommentsPatch = bytecodePatch(
    name = "Hide comments",
    description = "Blocks the comment endpoints so posts and reels have no comment section at all.",
    default = true
) {
    compatibleWith(COMPATIBILITY_INSTAGRAM)

    dependsOn(blockUrlBasePatch)

    execute {
        blockUrl(
            "/comments/",
            "/comment/",
            "/comment_likes/"
        )
    }
}
