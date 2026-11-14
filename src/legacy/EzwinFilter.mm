// 118 exact matches and 13 substring rules verified against ARM64 code.
#import "legacy/EzwinHooks.h"
#include <string.h>


uint64_t Ezwin_PathHash(const char* path) {
    uint64_t value = 0x14650fb0739d0383ULL;
    for (const unsigned char* p = (const unsigned char *)path; *p; ++p)
        value = (value ^ *p) * 0x100000001b3ULL;
    return value;
}

// FUN_03f607bc: exact-path hash dispatch, with collision-checking comparisons.
BOOL Ezwin_IsExactHiddenPath(const char* path) {
    if (!path) return NO;
    switch (Ezwin_PathHash(path)) {
        case 0x463025617ca5910ULL: return strcmp(path, "/usr/lib/libkrw") == 0;
        case 0x4dcf50a857bc386ULL: return strcmp(path, "/usr/lib/pspawn_payload-stg2.dylib") == 0;
        case 0x4e728339aa2a64cULL: return strcmp(path, "/private/var/lib/cydia") == 0;
        case 0x58a3553d10cd016ULL: return strcmp(path, "/usr/lib/libblackjack.dylib") == 0;
        case 0xa97d43c6da56256ULL: return strcmp(path, "/etc/apt") == 0;
        case 0xb5a21794d477446ULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries") == 0;
        case 0xde86086077f4444ULL: return strcmp(path, "/var/log/jailbreakd-stdout.log") == 0;
        case 0x112dc751e6f4be7eULL: return strcmp(path, "/var/run/FilzaHelper") == 0;
        case 0x163c0db8f8ef4c08ULL: return strcmp(path, "/.cydia_no_stash") == 0;
        case 0x17a6ce549670e424ULL: return strcmp(path, "/private/var/log/syslog") == 0;
        case 0x17f603d1f98878ceULL: return strcmp(path, "/usr/lib/libsubstitute.dylib") == 0;
        case 0x18d7391812ba49e8ULL: return strcmp(path, "/usr/lib/substrate/SubstrateBootstrap.dylib") == 0;
        case 0x1caff0ad745af481ULL: return strcmp(path, "/usr/bin/ssh") == 0;
        case 0x1cedd82e0265512eULL: return strcmp(path, "/var/cache/clutch.plist") == 0;
        case 0x23ccabe1d6f2eda7ULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist") == 0;
        case 0x245b270aa680e81eULL: return strcmp(path, "/pguntether") == 0;
        case 0x24a9f33ebc863af6ULL: return strcmp(path, "/etc/apt/sources.list.d/sileo.sources") == 0;
        case 0x24d72af0f5fa2769ULL: return strcmp(path, "/Applications/SBSettings.app") == 0;
        case 0x2521c3c5cce7096dULL: return strcmp(path, "/usr/lib/libjailbreak.dylib") == 0;
        case 0x2574c5e4d54f53a0ULL: return strcmp(path, "/var/lib/cydia") == 0;
        case 0x2a584c1916036f5cULL: return strcmp(path, "/bin/bash") == 0;
        case 0x30ec751d95758745ULL: return strcmp(path, "/usr/libexec/ssh-keysign") == 0;
        case 0x350eb8201b2e827eULL: return strcmp(path, "/bin/su") == 0;
        case 0x3556ba201b6c3b87ULL: return strcmp(path, "/bin/ls") == 0;
        case 0x3559a7201b6e5115ULL: return strcmp(path, "/bin/mv") == 0;
        case 0x3561dcf6678bb60dULL: return strcmp(path, "/Applications/Zebra.app") == 0;
        case 0x3584ddac01238f63ULL: return strcmp(path, "/bin/chmod") == 0;
        case 0x3a2d219333071dbaULL: return strcmp(path, "/usr/lib/tweakloader.dylib") == 0;
        case 0x3cef4155cb8bf227ULL: return strcmp(path, "/usr/libexec/sftp-server") == 0;
        case 0x3d69404bbb6685c5ULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/SSLKillSwitch2.plist") == 0;
        case 0x3e475fccf4669623ULL: return strcmp(path, "/usr/libexec/cydia/firmware.sh") == 0;
        case 0x44817064552e2f3aULL: return strcmp(path, "/jb/jailbreakd.plist") == 0;
        case 0x458c17ce53a7ddc6ULL: return strcmp(path, "/usr/lib/substrate") == 0;
        case 0x463bc87efa7aa29fULL: return strcmp(path, "/Library/PreferenceBundles/SubstitutePrefs.bundle") == 0;
        case 0x46a3d5b570a7bf3fULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/Veency.plist") == 0;
        case 0x47441b4920fa5e02ULL: return strcmp(path, "/usr/libexec/ellekit") == 0;
        case 0x4c94395925755288ULL: return strcmp(path, "/etc/clutch_cracked.plist") == 0;
        case 0x4fb777ba1366470dULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/LocalIAPStore.dylib") == 0;
        case 0x5231f437e3ffed7aULL: return strcmp(path, "/var/lib/clutch/overdrive.dylib") == 0;
        case 0x528b3e5617b9a671ULL: return strcmp(path, "/private/preboot/jb-") == 0;
        case 0x539e9c8fbd41d85eULL: return strcmp(path, "/Applications/FakeCarrier.app") == 0;
        case 0x582ece322edb2d49ULL: return strcmp(path, "/var/mobile/Library/Preferences/ABPattern") == 0;
        case 0x585aef4f9397db5bULL: return strcmp(path, "/Library/PreferenceBundles/LibertyPref.bundle") == 0;
        case 0x5a2b6b8432d4ea40ULL: return strcmp(path, "/private/var/cache/apt") == 0;
        case 0x5cc44bde856aa810ULL: return strcmp(path, "/Applications/FlyJB.app") == 0;
        case 0x5cf145ff4268b5a7ULL: return strcmp(path, "/System/Library/LaunchDaemons/com.ikey.bbot.plist") == 0;
        case 0x5df66657b2a89d61ULL: return strcmp(path, "/jb/lzma") == 0;
        case 0x5f1b83a39035f6d5ULL: return strcmp(path, "/usr/lib/libsubstrate.dylib") == 0;
        case 0x610037a48e2730dcULL: return strcmp(path, "/usr/lib/TweakInject") == 0;
        case 0x63198d6c983dc49aULL: return strcmp(path, "/usr/libexec/cydia") == 0;
        case 0x635e2a008bad2ee7ULL: return strcmp(path, "/var/binpack/Applications/loader.app") == 0;
        case 0x6566778ec2fc21c8ULL: return strcmp(path, "/private/var/mobile/Library/SBSettings/Themes") == 0;
        case 0x68249489da96651aULL: return strcmp(path, "/var/tmp/cydia.log") == 0;
        case 0x6b91afb23c6896adULL: return strcmp(path, "/var/lib/dpkg/info/mobilesubstrate.md5sums") == 0;
        case 0x6d19c5e28fe05faeULL: return strcmp(path, "/var/mobile/Media/.evasi0n7_installed") == 0;
        case 0x6f3bdc995b8af282ULL: return strcmp(path, "/.installed_unc0ver") == 0;
        case 0x7118a62ba4bd7913ULL: return strcmp(path, "/var/log/jailbreakd-stderr.log") == 0;
        case 0x716be4eff8b8add3ULL: return strcmp(path, "/var/containers/Bundle/tweaksupport") == 0;
        case 0x71ff95b425fa5490ULL: return strcmp(path, "/Applications/blackra1n.app") == 0;
        case 0x7289acc09a45e3daULL: return strcmp(path, "/etc/apt/sources.list.d/electra.list") == 0;
        case 0x73643dae8bd6e184ULL: return strcmp(path, "/Library/PreferenceBundles/libhbangprefs.bundle") == 0;
        case 0x73c1756efab915b9ULL: return strcmp(path, "/usr/lib/substrate/SubstrateLoader.dylib") == 0;
        case 0x75570f07a81d0262ULL: return strcmp(path, "/Applications/MxTube.app") == 0;
        case 0x756ad2b5c1c1505aULL: return strcmp(path, "/Library/PreferenceBundles/ABypassPrefs.bundle") == 0;
        case 0x78d5753341eeef10ULL: return strcmp(path, "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist") == 0;
        case 0x7c5303541b1a5ca9ULL: return strcmp(path, "/var/mobile/Library/Preferences/me.jjolano.shadow.plist") == 0;
        case 0x7cc692298f29fa78ULL: return strcmp(path, "/.bootstrapped_electra") == 0;
        case 0x7ef85029c43c540eULL: return strcmp(path, "/Applications/Snoop-itConfig.app") == 0;
        case 0x7ff9a86ad6df8f7dULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.dylib") == 0;
        case 0x82f28803904d622eULL: return strcmp(path, "/private/var/tmp/cydia.log") == 0;
        case 0x8976fcdc436d3afdULL: return strcmp(path, "/Frameworks") == 0;
        case 0x8b5402a2717b0f37ULL: return strcmp(path, "/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.plist") == 0;
        case 0x8d8a12de2a844616ULL: return strcmp(path, "/var/binpack") == 0;
        case 0x97b7a83b57687cbcULL: return strcmp(path, "/usr/sbin/sshd") == 0;
        case 0x987c938f1e41d50aULL: return strcmp(path, "/usr/lib/tweaks") == 0;
        case 0x99447fb7d375f1ceULL: return strcmp(path, "/Applications/Icy.app") == 0;
        case 0x99aa5b911bf33abaULL: return strcmp(path, "/usr/share/jailbreak/injectme.plist") == 0;
        case 0x9a847af36c0b82ceULL: return strcmp(path, "/var/db/stash") == 0;
        case 0xa00fc68d8738e928ULL: return strcmp(path, "/usr/lib/substrate/SubstrateInserter.dylib") == 0;
        case 0xa047b7be1f8fcd39ULL: return strcmp(path, "/jb/offsets.plist") == 0;
        case 0xa0adc9808f29e0dcULL: return strcmp(path, "SignedByEsign") == 0;
        case 0xa0d707e1d05fefe3ULL: return strcmp(path, "/bin/bzip2") == 0;
        case 0xa2c6fb841a8513e0ULL: return strcmp(path, "/etc/apt/undecimus/undecimus.list") == 0;
        case 0xa67b8354241dc6e8ULL: return strcmp(path, "/var/db/sudo") == 0;
        case 0xa680854f81bc181fULL: return strcmp(path, ".dylib") == 0;
        case 0xa987952f50f3a50cULL: return strcmp(path, "/var/log/apt") == 0;
        case 0xaa182df5473c8990ULL: return strcmp(path, "/usr/lib/libellekit.dylib") == 0;
        case 0xaf98e34967a71995ULL: return strcmp(path, "/Applications/RockApp.app") == 0;
        case 0xb063459d862a4d17ULL: return strcmp(path, "/private/var/stash") == 0;
        case 0xb092bb075040ade3ULL: return strcmp(path, "/Applications/Cydia.app") == 0;
        case 0xb20d71498334998aULL: return strcmp(path, "/etc/clutch.conf") == 0;
        case 0xb2d5d563a722bc26ULL: return strcmp(path, "/var/cache/clutch_cracked.plist") == 0;
        case 0xb5c0893f9cf3bfb7ULL: return strcmp(path, "/Library/TweakInject/TweakInject.dylib") == 0;
        case 0xb6f6f5dec8ae417cULL: return strcmp(path, "/etc/dropbear") == 0;
        case 0xb7b40920263b26bcULL: return strcmp(path, ".mobileprovision") == 0;
        case 0xb82ce734dbbb65c3ULL: return strcmp(path, "/Library/BawAppie/ABypass") == 0;
        case 0xbf16ebbdced4fa12ULL: return strcmp(path, "/usr/sbin/frida-server") == 0;
        case 0xbf28d1419e384672ULL: return strcmp(path, "/var/checkra1n.dmg") == 0;
        case 0xc9690cd3396248afULL: return strcmp(path, "/jb/libjailbreak.dylib") == 0;
        case 0xce2041eb5cafbf39ULL: return strcmp(path, "/usr/lib/ABSubLoader.dylib") == 0;
        case 0xd2a2610dee09ee2dULL: return strcmp(path, "/private/var/lib/apt") == 0;
        case 0xdb0780e91e7257e5ULL: return strcmp(path, "/var/run/sudo") == 0;
        case 0xdc2073deb26c0184ULL: return strcmp(path, "/var/cache/apt") == 0;
        case 0xe0d62fca41b97659ULL: return strcmp(path, "/Applications/Sileo.app") == 0;
        case 0xe22f9826e3787e27ULL: return strcmp(path, "/Library/PreferenceBundles/ShadowPreferences.bundle") == 0;
        case 0xe314788e8033bf9aULL: return strcmp(path, "/bin/cat") == 0;
        case 0xe4211b3681813aafULL: return strcmp(path, "/private/var/Users/") == 0;
        case 0xeb8ff7d9c19f1593ULL: return strcmp(path, "/Library/MobileSubstrate/CydiaSubstrate.dylib") == 0;
        case 0xeddceab636f8ce38ULL: return strcmp(path, "/usr/lib/libsubstitute.0.dylib") == 0;
        case 0xf29f7ffcbec57e72ULL: return strcmp(path, "/usr/lib/libhooker.dylib") == 0;
        case 0xf4df0c087a58e49bULL: return strcmp(path, "/Library/MobileSubstrate/MobileSubstrate.dylib") == 0;
        case 0xf7a79d7837873556ULL: return strcmp(path, "/Applications/IntelliScreen.app") == 0;
        case 0xf83b8e3703b6899bULL: return strcmp(path, "/usr/lib/ABDYLD.dylib") == 0;
        case 0xfc7bb424a68c459dULL: return strcmp(path, "/Library/PreferenceBundles/Cephei.bundle") == 0;
        case 0xfca00117c1ab85beULL: return strcmp(path, "embedded.mobileprovision") == 0;
        case 0xfcbd4830a084ac84ULL: return strcmp(path, "/Library/PreferenceBundles/FlyJBPrefs.bundle") == 0;
        case 0xfdebfd14a73eec8aULL: return strcmp(path, "/Applications/WinterBoard.app") == 0;
        case 0xfec2d257c6d78b0bULL: return strcmp(path, "/jb/amfid_payload.dylib") == 0;
        default: return NO;
    }
}

// FUN_03f58648: return true when the path remains visible.
BOOL Ezwin_IsVisiblePath(const char* path) {
    if (!path) return YES;
    if (Ezwin_IsExactHiddenPath(path)) return NO;
    static const char* hiddenFragments[] = {
        ".tweaked",
        ".rebuild",
        ".original",
        "/private/preboot",
        "TweakInject",
        "systemhook.dylib",
        "libswift_Concurrency.dylib",
        "libinjector.dylib",
        "jbroot",
        "SignedByEsign",
        "udcops",
        ".prelib",
        "embedded.mobileprovision",
    };
    for (size_t i = 0; i < sizeof(hiddenFragments) / sizeof(hiddenFragments[0]); i++)
        if (strstr(path, hiddenFragments[i])) return NO;
    return YES;
}

