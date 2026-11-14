#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

typedef struct {
    int skinID, weaponDefID, modelDefID;
    const char *name;
} EzwinSkin;

extern const EzwinSkin EzwinSkinCatalog[];
extern const size_t EzwinSkinCatalogCount;
NSString *EzwinSkinKey(int weaponDefID);

typedef uintptr_t (*EzwinWeaponSkinOriginal)(uintptr_t, uintptr_t, uintptr_t,
    int weaponDefID, uint32_t skinID, uintptr_t);
typedef uintptr_t (*EzwinGloveOriginal)(uintptr_t, uintptr_t, uintptr_t, uintptr_t actor, uintptr_t method);
typedef uintptr_t (*EzwinGloveLookup)(uintptr_t, uintptr_t, uintptr_t, uint32_t skinID, uintptr_t method);

@interface EzwinSkinChanger : NSObject
@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *selections;
@property(nonatomic, readonly) int gloveSkinID;
@property(nonatomic) BOOL settingsReady;
@property(nonatomic, copy) void (^writeSetting)(const char *key, uint32_t value);
@property(nonatomic, copy) void (^saveSettings)(void);
- (void)setSkinID:(int)skinID forKey:(NSString *)key;
- (void)toggleSkin:(const EzwinSkin *)skin;
- (NSArray<NSValue *> *)skinsForWeapon:(int)weaponDefID model:(int)modelDefID
    query:(NSString *)query;
- (uintptr_t)weaponSkinWithOriginal:(EzwinWeaponSkinOriginal)original enabled:(BOOL)enabled
    object:(uintptr_t)object argument1:(uintptr_t)argument1 argument2:(uintptr_t)argument2
    weaponDefID:(int)weaponDefID skinID:(uint32_t)skinID argument5:(uintptr_t)argument5;
- (uintptr_t)gloveWithOriginal:(EzwinGloveOriginal)original lookup:(EzwinGloveLookup)lookup
    enabled:(BOOL)enabled localActor:(uintptr_t)localActor object:(uintptr_t)object
    argument1:(uintptr_t)argument1 argument2:(uintptr_t)argument2 actor:(uintptr_t)actor method:(uintptr_t)method;
@end
