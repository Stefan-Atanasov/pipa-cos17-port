package com.port.pipa.helper;

/**
 * helper 2.5 (BUGS 150): the device identities of port step 3o (framework PipaAppIdentity). Keep in sync with
 * maintainer/propspoof/src/.../PipaAppIdentity.java: ROM step 8g compares both lists. The user choice goes to
 * Global "pipa_app_identity" = "pkg=key;pkg=key" ("real" = the real device); the framework reads it at app start.
 */
final class GameIdentity {
    private GameIdentity() { }

    static final String KEY = "pipa_app_identity";

    /** key, label (keys = PipaAppIdentity.profile()) */
    static final String[][] PROFILES = {
        { "rm_nova", "nubia RedMagic Nova (gaming tablet)" },
        { "rog6", "ASUS ROG Phone 6" },
        { "rog6d", "ASUS ROG Phone 6D" },
        { "y700", "Lenovo Legion Y700" },
        { "op8p", "OnePlus 8 Pro" },
        { "op9p", "OnePlus 9 Pro" },
        { "mi11tp", "Xiaomi 11T Pro" },
        { "mi13p", "Xiaomi 13 Pro" },
        { "pocof5", "POCO F5" },
        { "bs4", "Black Shark 4" },
        { "s24u", "Samsung Galaxy S24 Ultra" },
        { "pad6", "Xiaomi Pad 6 (as HyperOS; pen apps)" },
        { "pixel6", "Google Pixel 6" },
        { "pixelxl", "Google Pixel XL" },
    };

    /** package, profile key: the port defaults (step 3o) */
    static final String[] DEFAULTS = {
            "com.netflix.mediaclient", "pixel6",
            "com.google.android.apps.photos", "pixelxl",
            "com.netease.dfjsna", "rm_nova",
            "com.tencent.ig", "rm_nova",
            "Ultra Extreme", "rm_nova",
            "com.pubg.imobile", "rm_nova",
            "com.pubg.krmobile", "rm_nova",
            "com.rekoo.pubgm", "rm_nova",
            "com.tencent.tmgp.pubgmhd", "rm_nova",
            "com.vng.pubgmobile", "rm_nova",
            "com.tencent.tmgp.dfm", "rm_nova",
            "com.ea.gp.fifamobile", "rog6",
            "com.gameloft.android.ANMP.GloftA9HM", "rog6",
            "com.madfingergames.legends", "rog6",
            "com.pearlabyss.blackdesertm", "rog6",
            "com.pearlabyss.blackdesertm.gl", "rog6",
            "com.proxima.dfm", "rog6d",
            "com.activision.callofduty.shooter", "y700",
            "com.garena.game.codm", "y700",
            "com.tencent.tmgp.kr.codm", "y700",
            "com.vng.codmvn", "y700",
            "com.netease.lztgglobal", "op8p",
            "com.riotgames.league.wildrift", "op8p",
            "com.riotgames.league.wildrifttw", "op8p",
            "com.riotgames.league.wildriftvn", "op8p",
            "com.riotgames.league.teamfighttactics", "op8p",
            "com.riotgames.league.teamfighttacticstw", "op8p",
            "com.riotgames.league.teamfighttacticsvn", "op8p",
            "com.epicgames.fortnite", "op9p",
            "com.epicgames.portal", "op9p",
            "com.tencent.lolm", "op9p",
            "com.ea.gp.apexlegendsmobilefps", "mi11tp",
            "com.levelinfinite.hotta.gp", "mi11tp",
            "com.supercell.clashofclans", "mi11tp",
            "com.vng.mlbbvn", "mi11tp",
            "com.levelinfinite.sgameGlobal", "mi13p",
            "com.tencent.tmgp.sgame", "mi13p",
            "com.dts.freefiremax", "pocof5",
            "com.dts.freefireth", "pocof5",
            "com.mobile.legends", "pocof5",
            "com.proximabeta.mf.uamo", "bs4",
            "com.blizzard.diablo.immortal", "s24u",
            "com.orion.notein.global", "pad6",
            "com.onyx.galaxy.global.note", "pad6"
    };

    static String defaultFor(String pkg) {
        for (int i = 0; i < DEFAULTS.length; i += 2) if (DEFAULTS[i].equals(pkg)) return DEFAULTS[i + 1];
        return null;
    }

    static String label(String key) {
        if (key == null) return null;
        for (String[] p : PROFILES) if (p[0].equals(key)) return p[1];
        return key;
    }
}
