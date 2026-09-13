/*
 * Part of the Instagram patches fork:
 * https://github.com/luizslvr/instagram-patches
 *
 * Licensed under GPLv3. See the LICENSE file at the repository root.
 */

package app.morphe.patches.instagram.patches.distractionFree

import app.morphe.library.instagram.patches.blockUrl
import app.morphe.library.instagram.patches.blockUrlBasePatch
import app.morphe.patcher.Fingerprint
import app.morphe.patcher.extensions.InstructionExtensions.addInstructions
import app.morphe.patcher.patch.bytecodePatch
import app.morphe.patches.Constants.COMPATIBILITY_INSTAGRAM

/**
 * The one method a like reaches, whether it came from the heart button or a double tap.
 *
 * Anchored on the two analytics strings that only this path carries, exactly as the community
 * reference located it (InstaEclipse `DisableDoubleTapLikeHook`, instasave
 * `DoubleTapLikeFingerprint`). Both strings are constants inside the method body, and R8 does not
 * rewrite string constants, so the anchor survives reobfuscation of the enclosing class.
 */
private object LikeActionFingerprint : Fingerprint(
    returnType = "V",
    strings = listOf("double_tap_on_liked", "used_double_tap")
)

/**
 * Removes the ability to like a post or reel.
 *
 * Two levers, layered, because neither is sufficient alone:
 *
 *  1. Network. A like is a POST to `/api/v1/media/{media_id}/like/` (`/unlike/` to take one back).
 *     Blocking both substrings at `TigonServiceLayer.startRequest` means a like can never leave
 *     the device, so nothing is ever recorded server side. This is what makes the action genuinely
 *     gone rather than merely invisible.
 *
 *  2. UI. Instagram fills the heart optimistically, before the request resolves, so blocking the
 *     network alone would still show a heart that looks liked until the app next syncs. Returning
 *     immediately from the like action method removes that local feedback: tapping the heart does
 *     nothing at all.
 *
 * What this patch deliberately does NOT do: it does not remove the heart icon from the action row.
 * The heart lives in Instagram's own obfuscated view tree, rebuilt on every release, and no
 * maintained project in this ecosystem ships a "hide the heart widget" lever (brosssh, InstaEclipse
 * and instasave all stop at disabling the action, never the widget). Fingerprinting an obfuscated
 * view to set it GONE would break on essentially every update. Disabling the action and hiding the
 * count is the durable version of the same intent.
 *
 * VERIFY BEFORE SHIPPING:
 *   tools/dump_network_endpoints.sh   confirms `/like/` and `/unlike/` against the target APK.
 *   tools/verify_anchors.py           confirms the like method still resolves.
 */
@Suppress("unused")
val disableLikePatch = bytecodePatch(
    name = "Disable liking",
    description = "Blocks the like and unlike endpoints and stops the like action, so posts can no " +
            "longer be liked from the heart button or from a double tap.",
    default = true
) {
    compatibleWith(COMPATIBILITY_INSTAGRAM)

    dependsOn(blockUrlBasePatch)

    execute {
        // 1. Network: the like can never be sent.
        blockUrl(
            "/like/",
            "/unlike/"
        )

        // 2. UI: no optimistic heart, the tap becomes a no-op.
        LikeActionFingerprint.method.addInstructions(0, "return-void")
    }
}
