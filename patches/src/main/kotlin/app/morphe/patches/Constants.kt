package app.morphe.patches

import app.morphe.patcher.patch.AppTarget
import app.morphe.patcher.patch.Compatibility
import app.morphe.patcher.patch.SupportedAbi

object Constants {
    val COMPATIBILITY_INSTAGRAM = Compatibility(
        name = "Instagram",
        packageName = "com.instagram.android",
        targets = listOf(
            // The version the upstream patches were authored and validated against.
            AppTarget(
                version = "439.0.0.37.89",
                versionCodes = mapOf(
                    SupportedAbi.ARM64_V8A to 384510827,
                    SupportedAbi.ARMEABI_V7A to 384510838
                )
            ),
            // Added because 439 can no longer be obtained from any free mirror (as of 2026-09)
            // and so cannot actually be installed and tested by anyone new. This target exists to
            // make a build possible on a version that is still available.
            //
            // EXPERIMENTAL, and honestly so: the four distraction-free patches this fork adds have
            // had their fingerprint anchors and JSON keys confirmed against 446.0.0.49.77, but the
            // upstream patches in this bundle have NOT. Morphe fails loudly when a fingerprint does
            // not resolve, naming it, so a build attempt is itself the check for those.
            //
            // No versionCodes are declared: the ABI-to-versionCode mapping for 446 has not been
            // confirmed here, and declaring a wrong map would reject the correct file. The bundle
            // inspected (versionCode 385211303) carries density splits and no ABI splits at all,
            // so this version may not be split per ABI the way 439 was.
            AppTarget(
                version = "446.0.0.49.77",
                isExperimental = true
            )
        )
    )

    val COMPATIBILITY_CHARGEPRICE = Compatibility(
        name = "Chargeprice",
        packageName = "fr.chargeprice.app",
        appIconColor = 0x007AFF,
        targets = listOf(AppTarget(version = "3.9.2")),
    )

    val COMPATIBILITY_KOMOOT = Compatibility(
        name = "Komoot",
        packageName = "de.komoot.android",
        appIconColor = 0xECEBB4,
        targets = listOf(AppTarget(version = "2026.26.7")),
    )

    val COMPATIBILITY_MAPY = Compatibility(
        name = "Mapy.com",
        packageName = "cz.seznam.mapy",
        appIconColor = 0x32CF11,
        targets = listOf(AppTarget(version = "26.5.0")),
    )

    val COMPATIBILITY_PARK4NIGHT = Compatibility(
        name = "park4night",
        packageName = "fr.tramb.park4night",
        appIconColor = 0xFFFFFF,
        targets = listOf(AppTarget(version = "7.1.11")),
    )
}
