#import "features/skins/EzwinSkinChanger.h"

@implementation EzwinSkinChanger
- (instancetype)init {
    self = [super init];
    if (self) _selections = [NSMutableDictionary dictionary];
    return self;
}

- (void)setSkinID:(int)skinID forKey:(NSString *)key {
    if (!key.length) return;
    if (skinID > 0) self.selections[key] = @(skinID);
    else [self.selections removeObjectForKey:key];
    int glove = self.selections[@"Gloves (0)"].intValue;
    _gloveSkinID = glove > 0 ? glove : 0;
    if (self.settingsReady && self.writeSetting) {
        NSString *settingKey = [@"Skins " stringByAppendingString:key];
        self.writeSetting(settingKey.UTF8String, skinID > 0 ? (uint32_t)skinID : 0);
    }
    if (self.saveSettings) self.saveSettings();
}

- (void)toggleSkin:(const EzwinSkin *)skin {
    NSString *key = EzwinSkinKey(skin->weaponDefID);
    if (!key) return;
    int current = self.selections[key].intValue;
    [self setSkinID:current == skin->skinID ? 0 : skin->skinID forKey:key];
}

- (NSArray<NSValue *> *)skinsForWeapon:(int)weaponDefID model:(int)modelDefID
    query:(NSString *)query {
    NSString *search = query.lowercaseString;
    NSMutableArray<NSValue *> *visible = [NSMutableArray array];
    for (size_t i = 0; i < EzwinSkinCatalogCount; ++i) {
        const EzwinSkin *skin = EzwinSkinCatalog + i;
        if (search.length) {
            NSString *name = [NSString stringWithUTF8String:skin->name ?: ""];
            if ([name.lowercaseString rangeOfString:search].location == NSNotFound) continue;
        } else if (weaponDefID >= 0 && (skin->weaponDefID != weaponDefID ||
            (modelDefID > 0 && skin->modelDefID != modelDefID))) {
            continue;
        }
        [visible addObject:[NSValue valueWithPointer:skin]];
    }
    [visible sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        const EzwinSkin *left = (const EzwinSkin *)a.pointerValue;
        const EzwinSkin *right = (const EzwinSkin *)b.pointerValue;
        NSString *leftName = [NSString stringWithUTF8String:left->name ?: ""];
        NSString *rightName = [NSString stringWithUTF8String:right->name ?: ""];
        NSComparisonResult order = [leftName localizedCaseInsensitiveCompare:rightName];
        if (order != NSOrderedSame) return order;
        if (left->skinID == right->skinID) return NSOrderedSame;
        return left->skinID < right->skinID ? NSOrderedAscending : NSOrderedDescending;
    }];
    return visible;
}

- (uintptr_t)weaponSkinWithOriginal:(EzwinWeaponSkinOriginal)original enabled:(BOOL)enabled
    object:(uintptr_t)object argument1:(uintptr_t)argument1 argument2:(uintptr_t)argument2
    weaponDefID:(int)weaponDefID skinID:(uint32_t)skinID argument5:(uintptr_t)argument5 {
    if (enabled) {
        NSString *key = EzwinSkinKey(weaponDefID);
        int selected = self.selections[key].intValue;
        if (selected > 0) skinID = (uint32_t)selected;
    }
    return original(object, argument1, argument2, weaponDefID, skinID, argument5);
}

- (uintptr_t)gloveWithOriginal:(EzwinGloveOriginal)original lookup:(EzwinGloveLookup)lookup
    enabled:(BOOL)enabled localActor:(uintptr_t)localActor object:(uintptr_t)object
    argument1:(uintptr_t)argument1 argument2:(uintptr_t)argument2 actor:(uintptr_t)actor method:(uintptr_t)method {
    if (enabled && localActor && localActor == actor && self.gloveSkinID > 0) {
        uintptr_t replacement = lookup(object, argument1, argument2, (uint32_t)self.gloveSkinID, method);
        if (replacement) return replacement;
    }
    return original(object, argument1, argument2, actor, method);
}
@end
