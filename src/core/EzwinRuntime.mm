#include "unity/EzwinOffsets1900.h"
#include "core/EzwinRuntime.h"
#include "unity/EzwinUnity.h"
#include "hooks/EzwinStaticInline.h"
#include "features/audio/EzwinAudioHooks.h"
#include "core/EzwinDiagnostics.h"
#include "features/aim/EzwinAimMath.h"
#include "features/items/EzwinWeaponIcons.h"
#include "hooks/EzwinSymbolHooks.h"
#include "hooks/EzwinClientCallbacks.h"
#include "legacy/EzwinHooks.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include <math.h>
#include <TargetConditionals.h>
#include <dispatch/dispatch.h>
#if TARGET_OS_IOS
#import <DeviceCheck/DCAppAttestService.h>
#endif

#ifndef EZWIN_ENABLE_NATIVE_OBJC_HOOKS
#define EZWIN_ENABLE_NATIVE_OBJC_HOOKS 1
#endif
#ifndef EZWIN_MENU_ONLY
#define EZWIN_MENU_ONLY 0
#endif

static NSDictionary *installOptionalObjcHooks(void) {
#if EZWIN_ENABLE_NATIVE_OBJC_HOOKS
    return Ezwin_InstallNativeObjcHooks();
#else
    return @{@"enabled":@NO, @"installed":@[], @"missing":@[]};
#endif
}

static EzwinRuntimeOptions options;
static EzwinActorCollector collector;
static EzwinPlayerChamsState playerState;
static EzwinActorSoundState actorSounds;
static EzwinWorldESPState worldState;
static unsigned audioHookCount;
static unsigned viewHookCount;
static unsigned fileProbeHookCount;
static EzwinFileProbeOriginal originalFileProbe;
static uint32_t fileProbe(const char *path) { return EzwinFilterFileProbe(originalFileProbe,path); }
static void (*originalViewUpdate)(float,uintptr_t,uintptr_t);
static EzwinAimState aimState;
static bool aimResetRequested;
static EzwinItemState itemState;
static uint64_t aimUpdates;
static EzwinChamsController firstPerson;
static EzwinChamsDrawPacket viewSamples[2];
static EzwinSkinChanger *skins;
static void *playerShader, *visibleMaterial, *hiddenMaterial;
static bool playerShaderAttempted;
static bool installed, starting, optionsSet;
static size_t tableWrites, skinWrites;
static uint64_t actorUpdates, collectedActors, bindingAttempts;
static bool unityReady, cameraAvailable;
static NSString *startupStage = @"Runtime not started";
static NSString *observedUnityUUID = @"Not loaded";
static kern_return_t skinHookResult = KERN_FAILURE;
static NSDictionary *objcStatus;
static NSDictionary *runtimeProgress;
#if EZWIN_ENABLE_NATIVE_OBJC_HOOKS
static bool objcRetryQueued;
#endif
static pthread_mutex_t gameMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t progressMutex = PTHREAD_MUTEX_INITIALIZER;
static NSString *gameplayStage;
static void (*originalActor)(float, uintptr_t, uintptr_t);
static void (*originalPlayerDraw)(uintptr_t, uintptr_t, uintptr_t, uintptr_t);
static void (*originalViewDraw)(uintptr_t, uintptr_t, uintptr_t, uintptr_t);
static EzwinWeaponSkinOriginal originalWeapon;
static EzwinGloveOriginal originalGlove;
static EzwinGloveLookup gloveLookup;
static void patchAudioHooks(void);
static void preparePlayerMaterials(const EzwinRuntimeOptions &options);
static void prepareViewMaterials(const EzwinRuntimeOptions &options);
static uintptr_t weaponSkin(uintptr_t, uintptr_t, uintptr_t, int, uint32_t, uintptr_t);
static uintptr_t gloveSkin(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

static void retryObjcHooks(void) {
#if EZWIN_ENABLE_NATIVE_OBJC_HOOKS
    if(__atomic_exchange_n(&objcRetryQueued,true,__ATOMIC_ACQ_REL))return;
    dispatch_async(dispatch_get_main_queue(),^{
        @autoreleasepool {
            @synchronized ([NSProcessInfo processInfo]) { objcStatus=installOptionalObjcHooks(); }
            __atomic_store_n(&objcRetryQueued,false,__ATOMIC_RELEASE);
        }
    });
#endif
}

static uintptr_t pointer(uintptr_t address) { uintptr_t value; memcpy(&value, (void *)address, 8); return value; }
static int integer(uintptr_t address) { int value; memcpy(&value, (void *)address, 4); return value; }
static uint64_t nanoseconds(void) {
    struct timespec now; clock_gettime(CLOCK_UPTIME_RAW, &now);
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}
static uintptr_t lockObject(void) { return (uintptr_t)(__bridge void *)[NSProcessInfo processInfo]; }
static void setGameplayStage(NSString *stage) {
    pthread_mutex_lock(&progressMutex); gameplayStage = stage; pthread_mutex_unlock(&progressMutex);
}

// UI operations never wait for a game callback or a Unity API call.
struct GameGuard {
    bool locked;
    GameGuard() : locked(pthread_mutex_trylock(&gameMutex) == 0) { }
    ~GameGuard() {
        if (!locked) return;
        pthread_mutex_lock(&progressMutex);
        runtimeProgress = @{@"actorUpdates":@(actorUpdates), @"collectedActors":@(collectedActors),
                @"bindingAttempts":@(bindingAttempts), @"bindingsReady":@(unityReady),
                @"cameraAvailable":@(cameraAvailable), @"localActorAvailable":@(collector.localActor != 0),
                @"audioHooks":@(audioHookCount),@"aimUpdates":@(aimUpdates),
                @"itemCount":@(itemState.count)};
        pthread_mutex_unlock(&progressMutex);
        pthread_mutex_unlock(&gameMutex);
    }
};

static void renderActor(EzwinCollectedActor *actor, const EzwinRuntimeOptions &options) {
    if (!actor || actor->esp.alpha <= 0 || !options.esp.enabled) return;
    EzwinPrepareActorLabels(actor, &options.esp, options.textHeight > 0 ? options.textHeight : 11,
        options.flagHeight > 0 ? options.flagHeight : 8, nanoseconds());
    EzwinRenderActorESP(&actor->esp, &options.esp, EzwinProjectESPPosition, nullptr, &collector.projection);
}

static void actorUpdate(float delta, uintptr_t actor, uintptr_t method) {
    originalActor(delta, actor, method);
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    GameGuard guard; if (!guard.locked) return;
    {
        ++actorUpdates;
        if (!options.playerChams && !options.selfChams) playerShaderAttempted = false;
        if (!options.esp.enabled && !options.playerChams && !options.selfChams && !options.firstPersonChams && !options.worldESP.sound && !options.aim.selection.enabled && !options.items.enabled) {
            itemState.count=0;
            setGameplayStage(@"Features disabled; forwarding game callbacks");
            return;
        }
        EzwinTraceCheckpoint(0, "actor: feature path entered");
        if (!unityReady) {
            EzwinTraceCheckpoint(1, "actor: binding verified Unity entries");
            ++bindingAttempts; unityReady = EzwinBindUnity1900(EzwinUnityBase());
        }
        if (!unityReady) { setGameplayStage(@"Waiting for Unity method bindings"); return; }
        EzwinTraceCheckpoint(2, "actor: Unity entries bound");
        EzwinTraceCheckpoint(3, "actor: getting frame");
        int32_t frame = EzwinUnityFrame();
        bool newFrame = frame == -1 || collector.frame != frame;
        collector.frame = frame;
        collector.projection.api = {EzwinUnityTransform, EzwinUnityProjection, EzwinUnityWorldToLocal};
        collector.projection.width = options.esp.screenWidth;
        collector.projection.height = options.esp.screenHeight;
        EzwinTraceCheckpoint(4, "actor: resolving local actor and team");
        collector.localActor = EzwinUnityLocalActor();
        collector.localTeam = -1;
        if (collector.localActor) {
            uintptr_t controller = pointer(collector.localActor + EzwinField_ActorController), player = controller ? pointer(controller + EzwinField_ControllerPlayer) : 0;
            uintptr_t team = player ? pointer(player + EzwinField_PlayerTeam) : 0;
            if (team) collector.localTeam = integer(team + EzwinField_ScalarValue);
        }
        EzwinTraceCheckpoint(5, "actor: reading visibility mask");
        collector.layerMask = options.visibilityMask == -1 ? EzwinUnityVisibilityMask() : options.visibilityMask;
        collector.allBoneVisibility = options.esp.skeleton || options.esp.hitboxes;
        collector.sampleHitboxes = options.esp.hitboxes || options.esp.hitboxValues || options.esp.box3D;
        collector.rendererHistory = nullptr;
        collector.sound = &actorSounds;
        collector.fields = 0;
        collector.aimBone=EzwinTargetBoneIndex(options.aim.selection.targetBone);
        if (options.esp.enabled || options.worldESP.sound) collector.fields |= EzwinCollectPosition;
        if(options.aim.selection.enabled)collector.fields|=EzwinCollectPosition|EzwinCollectAim;
        if (options.esp.enabled) {
            collector.fields |= EzwinCollectGeometry;
            if (options.esp.skeleton || options.esp.hitboxes || options.esp.headCircle || options.worldESP.arrows)
                collector.fields |= EzwinCollectVisibility;
            if (options.esp.placement.enabled[1]) collector.fields |= EzwinCollectName;
            if (options.esp.placement.enabled[8] || options.esp.placement.enabled[13]) collector.fields |= EzwinCollectStatistics;
            if (options.esp.placement.enabled[4] || options.esp.placement.enabled[9]) collector.fields |= EzwinCollectArmor;
            if (options.esp.placement.enabled[11]) collector.fields |= EzwinCollectFlash;
            if (options.esp.placement.enabled[10]) collector.fields |= EzwinCollectScope;
            if (options.esp.placement.enabled[12]) collector.fields |= EzwinCollectProtection;
            if (options.esp.placement.enabled[6] || options.esp.placement.enabled[7]) collector.fields |= EzwinCollectWeapon;
        }
        EzwinTraceCheckpoint(6, "actor: getting gameplay camera");
        void *camera = EzwinUnityCamera();
        cameraAvailable = camera != nullptr;
        if (!camera) { setGameplayStage(@"Waiting for the gameplay camera"); return; }
        setGameplayStage(@"Collecting gameplay actors");
        EzwinTraceCheckpoint(7, "actor: updating projection matrices");
        EzwinUpdateProjection(&collector.projection, camera, frame);
        if (newFrame) {
            if(options.items.enabled) {
                void *cameraTransform=EzwinUnityTransform(camera);
                if(!EzwinUnityValid(cameraTransform))return;
                EzwinPosition origin=EzwinMatrixPosition(EzwinUnityLocalToWorld(cameraTransform));
                const EzwinItemAPI api={EzwinUnityValid,EzwinUnityTransform,EzwinUnityLocalToWorld,
                    EzwinWeaponIconTexture,EzwinWeaponName};
                EzwinCollectItems(&itemState,EzwinUnityContext(),origin,&collector.projection,&api);
                EzwinTraceCheckpoint(63,"items: native registry sampled");
                EzwinRenderItems(&itemState,&collector.projection,options.items.color);
            } else itemState.count=0;
            if (options.playerChams || options.selfChams) preparePlayerMaterials(options);
            if (options.firstPersonChams) prepareViewMaterials(options);
            if (options.worldESP.sound || (options.esp.enabled &&
                (options.esp.placement.enabled[14] || options.esp.placement.enabled[15]))) {
                EzwinTraceCheckpoint(8, "actor: installing sound observers");
                patchAudioHooks();
            }
            EzwinTraceCheckpoint(9, "actor: advancing fades");
            EzwinAdvanceActorFades(&collector, nanoseconds());
            for (int i = 0; i < 32; ++i)
                if (collector.actors[i].esp.health <= 0) renderActor(collector.actors + i, options);
        }
        if (!options.esp.enabled && !options.playerChams && !options.selfChams && !options.worldESP.sound && !options.aim.selection.enabled) return;
        EzwinTraceCheckpoint(10, "actor: collecting actor fields");
        EzwinCollectedActor *sample = EzwinCollectActor(&collector, actor);
        if (sample) ++collectedActors;
        if (sample && (options.playerChams || options.selfChams)) {
            EzwinTraceCheckpoint(11, "actor: setting renderer occlusion");
            bool selected = sample->esp.self ? options.selfChams : options.playerChams && sample->esp.eligible;
            EzwinUnityRendererOcclusion(sample->renderer, !(selected && sample->esp.health > 0));
            EzwinTraceCheckpoint(14, "actor: renderer occlusion call completed");
        }
        EzwinTraceCheckpoint(12, "actor: publishing ESP commands");
        renderActor(sample, options);
        EzwinTraceCheckpoint(13, "actor: feature callback completed");
    }
}

static void viewUpdate(float delta,uintptr_t actor,uintptr_t method) {
    originalViewUpdate(delta,actor,method);
    EzwinRuntimeOptions value;EzwinGetRuntimeOptions(&value);
    if(!value.aim.selection.enabled)return;
    GameGuard guard;if(!guard.locked)return;
    if(__atomic_exchange_n(&aimResetRequested,false,__ATOMIC_ACQ_REL))aimState={};
    EzwinTraceCheckpoint(60,"view: feature callback entered");
    if(!unityReady) { ++bindingAttempts;unityReady=EzwinBindUnity1900(EzwinUnityBase()); }
    if(!unityReady)return;
    uintptr_t local=EzwinUnityLocalActor();
    if(!actor || actor!=local)return;
    void *camera=EzwinUnityCamera(),*transform=camera?EzwinUnityTransform(camera):nullptr;
    if(!EzwinUnityValid(transform)) { aimState={};return; }
    EzwinMatrix matrix=EzwinUnityLocalToWorld(transform);
    EzwinPosition origin=EzwinMatrixPosition(matrix);
    int32_t frame=EzwinUnityFrame();
    int mask=value.visibilityMask==-1?0x8400:value.visibilityMask;
    collector.projection.api={EzwinUnityTransform,EzwinUnityProjection,EzwinUnityWorldToLocal};
    collector.projection.width=value.esp.screenWidth;collector.projection.height=value.esp.screenHeight;
    collector.projection.initialized=false;EzwinUpdateProjection(&collector.projection,camera,frame);
    if(!value.aim.selection.enabled || EzwinUnityHealth(local)<=0) { aimState={};return; }
    EzwinAimCandidate candidates[32]={};int count=0;
    int bone=EzwinTargetBoneIndex(value.aim.selection.targetBone);
    for(int i=0;i<32;++i) {
        const EzwinCollectedActor *sample=collector.actors+i;
        if(!sample->esp.actor || sample->esp.self || !sample->esp.eligible || sample->esp.health<=5 ||
            (frame>=0 && (sample->sampledFrame<frame-1 || sample->sampledFrame>frame)) ||
            !EzwinUnityValid((void *)sample->esp.actor))continue;
        EzwinAimCandidate candidate={};candidate.actor=sample->esp.actor;candidate.state=1;
        candidate.health=sample->esp.health;candidate.boneCount=EzwinBoneCount(candidate.actor);
        candidate.boneAvailable=candidate.boneCount>bone && (sample->sampledBones&(1u<<bone));candidate.root=sample->world;
        candidate.bone=sample->worldBones[bone];candidate.screen=EzwinProjectPosition(&collector.projection,candidate.bone);
        candidate.visible=!value.aim.selection.visibilityCheck || !EzwinUnityLineBlocked(origin,candidate.bone,mask);
        candidates[count++]=candidate;
    }
    value.aim.selection.width=value.esp.screenWidth;value.aim.selection.height=value.esp.screenHeight;
    value.aim.selection.firing=EzwinUnityFiring(local);
    EzwinViewAngles output;
    if(EzwinAdvanceAim(&aimState,candidates,count,local,origin,EzwinUnityViewAngles(local),value.aim,delta,&output)) {
        EzwinUnitySetViewAngles(local,output);++aimUpdates;
        EzwinTraceCheckpoint(61,"aim: selected target angles applied");
    }
}

struct DrawRange { uintptr_t list; EzwinChamsDrawPacket *packets; int count; };
static DrawRange drawRange(uintptr_t context) {
    uintptr_t list = context ? pointer(context + EzwinField_DrawContextList) : 0;
    int count = list ? integer(list + EzwinField_DrawListCount) : 0;
    uintptr_t array = list ? pointer(list + EzwinField_DrawListArray) : 0;
    if (!array || count < 0 || count > integer(array + EzwinField_ArrayLength)) return {list, nullptr, 0};
    return {list, (EzwinChamsDrawPacket *)(array + EzwinField_ArrayData), count};
}
static void appendPacket(void *context, const EzwinChamsDrawPacket *packet) {
    ((void (*)(uintptr_t, const EzwinChamsDrawPacket *, void *))(EzwinUnityBase() + EzwinUF_AppendPacket))((uintptr_t)context, packet, nullptr);
}

static void preparePlayerMaterials(const EzwinRuntimeOptions &options) {
    const EzwinChamsAPI *api = EzwinUnityChamsAPI();
    if (!api) return;
    EzwinTraceCheckpoint(33, "actor: loading player shader");
    if (!EzwinUnityValid(playerShader)) {
        playerShader = nullptr;
        if (playerShaderAttempted) return;
        playerShaderAttempted = true;
        playerShader = EzwinLoadShader(EzwinLoadShaderBundle(nullptr), "chamsshader");
    }
    if (!playerShader) {
        EzwinTraceCheckpoint(49, "actor: player shader unavailable; repeated loading stopped");
        setGameplayStage(@"Player shader unavailable; toggle chams to retry");
        return;
    }
    EzwinTraceCheckpoint(50, "actor: player shader ready");
    if (!EzwinUnityValid(visibleMaterial)) visibleMaterial = nullptr;
    if (!EzwinUnityValid(hiddenMaterial)) hiddenMaterial = nullptr;
    EzwinTraceCheckpoint(34, "actor: creating player materials");
    EzwinEnsurePlayerChamsMaterial(&visibleMaterial, playerShader, api, 8, 4000);
    EzwinEnsurePlayerChamsMaterial(&hiddenMaterial, playerShader, api, 5, 4001);
    EzwinMaterialColor visible, hidden;
    EzwinPlayerChamsColors(options.rainbow, true, EzwinUnityRealtime(), options.visibleColor, options.hiddenColor, &visible, &hidden);
    EzwinUpdatePlayerChamsMaterials(&playerState, &api->material, visibleMaterial, hiddenMaterial, visible, hidden, options.player);
}

static void prepareViewMaterials(const EzwinRuntimeOptions &options) {
    const EzwinChamsAPI *api = EzwinUnityChamsAPI();
    if (!api || (!viewSamples[0].mesh && !viewSamples[1].mesh)) return;
    EzwinTraceCheckpoint(41, "actor: preparing view shader and materials");
    EzwinChamsDrawPacket samples[2] = {viewSamples[0], viewSamples[1]};
    for (int i = 0; i < 2; ++i)
        if (!EzwinUnityValid(samples[i].material)) samples[i].material = nullptr;
    EzwinChamsMeshes meshes = {samples[0].mesh, samples[1].mesh, nullptr, 0};
    EzwinApplyFirstPersonChams(&firstPerson, api, meshes, samples, 0, 2,
        true, options.firstPerson, &options.viewStretch);
    EzwinTraceCheckpoint(42, "actor: view materials prepared");
}

static void playerDraw(uintptr_t renderer, uintptr_t context, uintptr_t renderParameters, uintptr_t method) {
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    bool packetsNeeded, recordRenderer;
    packetsNeeded = options.playerChams || options.selfChams;
    recordRenderer = packetsNeeded;
    if (packetsNeeded) EzwinTraceCheckpoint(32, "player draw: reading packet range");
    DrawRange before = packetsNeeded ? drawRange(context) : DrawRange{};
    originalPlayerDraw(renderer, context, renderParameters, method);
    if (!recordRenderer) return;
    GameGuard guard; if (!guard.locked) return;
    {
        if (renderer && recordRenderer)
            EzwinRecordChamsRenderer(&playerState, renderer, collector.frame);
    }
    if (!packetsNeeded) return;
    DrawRange after = drawRange(context);
    if (!after.packets || before.count >= after.count) return;
    {
        bool tracked = false;
        for (int i = 0; i < 32; ++i) {
            EzwinCollectedActor *actor = collector.actors + i;
            bool selected = actor->esp.self ? options.selfChams : options.playerChams && actor->esp.eligible;
            if (actor->renderer == renderer && selected && actor->esp.health > 0) { tracked = true; break; }
        }
        if ((!options.playerChams && !options.selfChams) || !tracked || !visibleMaterial || !hiddenMaterial) return;
        EzwinTraceCheckpoint(35, "player draw: appending material passes");
        EzwinApplyPlayerChamsPackets(after.packets, before.count, after.count, true, tracked,
            visibleMaterial, hiddenMaterial, appendPacket, (void *)context);
        EzwinTraceCheckpoint(36, "player draw: completed");
    }
}

static void viewDraw(uintptr_t object, uintptr_t context, uintptr_t renderParameters, uintptr_t method) {
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    bool enabled = options.firstPersonChams;
    if (enabled) EzwinTraceCheckpoint(40, "view draw: reading packet range");
    DrawRange before = enabled ? drawRange(context) : DrawRange{};
    originalViewDraw(object, context, renderParameters, method);
    if (!enabled) return;
    DrawRange after = drawRange(context);
    if (!object || !after.packets || before.count >= after.count) return;
    GameGuard guard; if (!guard.locked) return;
    {
        if (!options.firstPersonChams) return;
        uintptr_t array = pointer(object + EzwinField_ViewMeshList);
        int count = array ? integer(array + EzwinField_ArrayLength) : 0;
        EzwinChamsMeshes meshes = {(void *)pointer(object + EzwinField_ViewMeshMain), (void *)pointer(object + EzwinField_ViewMeshHands),
            count > 0 && count < 256 ? (void **)(array + EzwinField_ArrayData) : nullptr, count};
        for (int i = before.count; i < after.count; ++i) {
            EzwinChamsDrawPacket *packet = after.packets + i;
            int group = EzwinChamsMeshGroup(packet->mesh, meshes);
            if (group < 0 || !options.firstPerson[group].mode) continue;
            viewSamples[group] = *packet;
            if (firstPerson.materials[group]) packet->material = firstPerson.materials[group];
        }
        EzwinTraceCheckpoint(43, "view draw: queued samples and applied prepared materials");
    }
}

static uintptr_t weaponSkin(uintptr_t object, uintptr_t a, uintptr_t b, int weapon, uint32_t skin, uintptr_t c) {
    int selected = 0;
    @synchronized ((__bridge id)(void *)lockObject()) {
        if (options.skinChanger) selected = EzwinRuntimeSkinChanger().selections[EzwinSkinKey(weapon)].intValue;
    }
    return originalWeapon(object, a, b, weapon, selected > 0 ? (uint32_t)selected : skin, c);
}
static uintptr_t gloveSkin(uintptr_t object, uintptr_t a, uintptr_t b, uintptr_t actor, uintptr_t method) {
    int selected = 0;
    @synchronized ((__bridge id)(void *)lockObject()) {
        if (options.skinChanger) selected = EzwinRuntimeSkinChanger().gloveSkinID;
    }
    if (selected > 0 && actor && actor == EzwinUnityLocalSkinActor()) {
        uintptr_t replacement = gloveLookup(object, a, b, (uint32_t)selected, method);
        if (replacement) return replacement;
    }
    return originalGlove(object, a, b, actor, method);
}

static bool matchesImage(const mach_header_64 *header) {
    if (header->magic != MH_MAGIC_64) return false;
    const load_command *command = (const load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (command->cmd == LC_UUID) {
            const uint8_t *value = ((const uuid_command *)command)->uuid;
            for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
                if (_dyld_get_image_header(i) != (const mach_header *)header) continue;
                const char *path = _dyld_get_image_name(i);
                if (path && strstr(path, "UnityFramework")) {
                    @synchronized ((__bridge id)(void *)lockObject()) {
                        observedUnityUUID = [NSString stringWithFormat:
                            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                            value[0],value[1],value[2],value[3],value[4],value[5],value[6],value[7],
                            value[8],value[9],value[10],value[11],value[12],value[13],value[14],value[15]];
                        if (memcmp(value, EzwinUnityUUID, 16)) startupStage = @"Unity UUID differs from the analyzed 1.90.0 build";
                    }
                }
                break;
            }
            return !memcmp(value, EzwinUnityUUID, 16);
        }
        command = (const load_command *)((uintptr_t)command + command->cmdsize);
    }
    return false;
}

static bool writePointer(uintptr_t address, uintptr_t expected, uintptr_t replacement) {
    if (pointer(address) == replacement) return true;
    if (pointer(address) != expected) return false;
    vm_address_t region = address;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) return false;
    if (object) mach_port_deallocate(mach_task_self(), object);
    vm_address_t page = address & ~(vm_page_size - 1);
    bool writable = info.protection & VM_PROT_WRITE;
    if (!writable && vm_protect(mach_task_self(), page, vm_page_size, false, info.protection | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return false;
    __atomic_store_n((uintptr_t *)address, replacement, __ATOMIC_RELEASE);
    if (!writable) vm_protect(mach_task_self(), page, vm_page_size, false, info.protection);
    return true;
}

static void audioObserved(unsigned category, EzwinPosition position) {
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    GameGuard guard; if (!guard.locked) return;
    {
        EzwinCollectedActor *nearest = nullptr;
        float best = 6.25f;
        for (int i = 0; i < 32; ++i) {
            EzwinCollectedActor *actor = collector.actors + i;
            if (!actor->esp.actor || !actor->esp.eligible || actor->esp.self || actor->esp.health <= 0) continue;
            float x = actor->world.x - position.x, z = actor->world.z - position.z;
            float distance = z * z + x * x;
            if (distance < best) { best = distance; nearest = actor; }
        }
        if (nearest) {
            EzwinRecordActorSound(&actorSounds, nearest->esp.actor, category, nanoseconds());
            if (category == 2 && options.worldESP.sound && options.worldESP.shots)
                EzwinRecordWorldShot(&worldState, nearest->esp.actor, nearest->world);
        }
    }
}

static void patchAudioHooks(void) {
    if (audioHookCount == 3) return;
    uintptr_t base = EzwinUnityBase();
    if (!base) return;
    // These IL2CPP pointer slots are initialized after image loading; wait for all four originals.
    EzwinTraceCheckpoint(53, "audio: reading initialized call slots");
    uintptr_t play = pointer(base + EzwinSlot_AudioPlay), position = pointer(base + EzwinSlot_TransformSetPosition);
    uintptr_t clip = pointer(base + EzwinSlot_AudioClip), name = pointer(base + EzwinSlot_AudioName);
    if (!play || !position || !clip || !name) return;
    if (play == (uintptr_t)EzwinAudioPlayHook || position == (uintptr_t)EzwinAudioPositionHook ||
        clip == (uintptr_t)EzwinAudioClipHook) return;
    EzwinTraceCheckpoint(54, "audio: configuring original callbacks");
    EzwinConfigureAudioHooks((EzwinAudioPositionOriginal)position, (EzwinAudioClipOriginal)clip,
        (EzwinAudioPlayOriginal)play, (EzwinAudioName)name, audioObserved);
    EzwinTraceCheckpoint(55, "audio: installing position observer");
    bool a = writePointer(base + EzwinSlot_TransformSetPosition, position, (uintptr_t)EzwinAudioPositionHook);
    EzwinTraceCheckpoint(56, "audio: installing generator observer");
    bool b = writePointer(base + EzwinSlot_AudioClip, clip, (uintptr_t)EzwinAudioClipHook);
    EzwinTraceCheckpoint(57, "audio: installing playback observer");
    bool c = writePointer(base + EzwinSlot_AudioPlay, play, (uintptr_t)EzwinAudioPlayHook);
    if (a && b && c) { audioHookCount = 3; EzwinTraceCheckpoint(58, "audio: all observers installed"); }
    else {
        EzwinTraceCheckpoint(59, "audio: incomplete installation; restoring originals");
        if (a) writePointer(base + EzwinSlot_TransformSetPosition, (uintptr_t)EzwinAudioPositionHook, position);
        if (b) writePointer(base + EzwinSlot_AudioClip, (uintptr_t)EzwinAudioClipHook, clip);
        if (c) writePointer(base + EzwinSlot_AudioPlay, (uintptr_t)EzwinAudioPlayHook, play);
    }
}

static void imageAdded(const mach_header *image, intptr_t) {
    retryObjcHooks();
    if (installed || !matchesImage((const mach_header_64 *)image)) return;
    @synchronized ((__bridge id)(void *)lockObject()) {
        if (installed) return;
        uintptr_t base = (uintptr_t)image;
        const EzwinStaticRoute routes[] = {
            {EzwinUF_ActorUpdate, (uintptr_t)actorUpdate}, {EzwinUF_PlayerDraw, (uintptr_t)playerDraw},
            {EzwinUF_ViewDraw, (uintptr_t)viewDraw}, {EzwinUF_WeaponSkin, (uintptr_t)weaponSkin},
            {EzwinUF_GloveSkin, (uintptr_t)gloveSkin}
        };
        if (!EzwinValidateStaticRoutes(base, routes, 5)) {
            startupStage = @"Static hook blocks missing or occupied. Install the prepared UnityFramework copy.";
            return;
        }
        // Set every original before any route becomes callable on another thread.
        originalActor = (decltype(originalActor))EzwinStaticOriginal(base, routes[0].target);
        originalPlayerDraw = (decltype(originalPlayerDraw))EzwinStaticOriginal(base, routes[1].target);
        originalViewDraw = (decltype(originalViewDraw))EzwinStaticOriginal(base, routes[2].target);
        originalWeapon = (EzwinWeaponSkinOriginal)EzwinStaticOriginal(base, routes[3].target);
        originalGlove = (EzwinGloveOriginal)EzwinStaticOriginal(base, routes[4].target);
        gloveLookup = (EzwinGloveLookup)(base + EzwinUF_GloveLookup);
        EzwinUnitySetBase(base);
        if (!EzwinActivateStaticRoutes(base, routes, 5)) { startupStage = @"Static route activation failed"; return; }
        const EzwinStaticRoute viewRoute={EzwinUF_ViewUpdate,(uintptr_t)viewUpdate};
        if(EzwinValidateStaticRoutes(base,&viewRoute,1)) {
            originalViewUpdate=(decltype(originalViewUpdate))EzwinStaticOriginal(base,viewRoute.target);
            if(EzwinActivateStaticRoutes(base,&viewRoute,1))viewHookCount=1;
        }
        const EzwinStaticRoute probeRoute={EzwinUF_FileProbe,(uintptr_t)fileProbe};
        if(EzwinValidateStaticRoutes(base,&probeRoute,1)) {
            originalFileProbe=(EzwinFileProbeOriginal)EzwinStaticOriginal(base,probeRoute.target);
            if(EzwinActivateStaticRoutes(base,&probeRoute,1))fileProbeHookCount=1;
        }
        skinWrites = 2; skinHookResult = KERN_SUCCESS;
        EzwinInstallClientCallbacks(base);
        objcStatus = installOptionalObjcHooks();
        installed = true;
        startupStage = @"Static hooks installed; waiting for actor updates";
    }
}

#ifdef EZWIN_HOOK_TESTING
extern "C" void EzwinTestCollectedActor(const EzwinCollectedActor *sample) { collector.actors[0]=*sample; }
extern "C" void EzwinTestStaticImage(const mach_header *image) { imageAdded(image, 0); }
extern "C" void EzwinTestViewOriginal(uintptr_t original,uintptr_t *callback) {
    originalViewUpdate=(decltype(originalViewUpdate))original;*callback=(uintptr_t)viewUpdate;
}
extern "C" void EzwinTestOriginals(const uintptr_t *originals, uintptr_t *callbacks) {
    originalActor = (decltype(originalActor))originals[0];
    originalPlayerDraw = (decltype(originalPlayerDraw))originals[1];
    originalViewDraw = (decltype(originalViewDraw))originals[2];
    originalWeapon = (EzwinWeaponSkinOriginal)originals[3];
    originalGlove = (EzwinGloveOriginal)originals[4];
    const uintptr_t replacements[] = {(uintptr_t)actorUpdate, (uintptr_t)playerDraw,
        (uintptr_t)viewDraw, (uintptr_t)weaponSkin, (uintptr_t)gloveSkin};
    memcpy(callbacks, replacements, sizeof(replacements));
}
#endif

EzwinSkinChanger *EzwinRuntimeSkinChanger(void) {
    if (!skins) skins = [EzwinSkinChanger new];
    return skins;
}
void EzwinSetRuntimeOptions(const EzwinRuntimeOptions *value) {
    if (!value) return;
    @synchronized ((__bridge id)(void *)lockObject()) {
        if(options.aim.selection.enabled!=value->aim.selection.enabled ||
            options.aim.selection.targetBone!=value->aim.selection.targetBone)
            __atomic_store_n(&aimResetRequested,true,__ATOMIC_RELEASE);
        options = *value; optionsSet = true;
    }
}
bool EzwinGetRuntimeOptions(EzwinRuntimeOptions *value) {
    if (!value) return false;
    @synchronized ((__bridge id)(void *)lockObject()) {
        *value = options;
        if (!optionsSet) value->visibilityMask = -1;
        return optionsSet;
    }
}
void EzwinStartRuntime(void) {
    @synchronized ((__bridge id)(void *)lockObject()) {
        if (starting) return;
        starting = true;
        EzwinStartDiagnostics();
        if (EZWIN_MENU_ONLY) { startupStage = @"Menu-only test build"; return; }
        if (!optionsSet) options.visibilityMask = -1;
        collector.frame = -1;
#if EZWIN_ENABLE_NATIVE_OBJC_HOOKS && TARGET_OS_IOS
        (void)[DCAppAttestService class];
#endif
        objcStatus = installOptionalObjcHooks();
        startupStage = @"Waiting for the matching Unity image";
        EzwinInstallSymbolHooks();
        _dyld_register_func_for_add_image(imageAdded);
#if EZWIN_ENABLE_NATIVE_OBJC_HOOKS && TARGET_OS_IOS
        // Some frameworks replace methods after their image-added callback.
        // Audit again after startup without continuously fighting swizzlers.
        const int auditSeconds[]={1,3,10};
        for(int seconds : auditSeconds)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)seconds*NSEC_PER_SEC),
            dispatch_get_main_queue(),^{ retryObjcHooks(); });
#endif
    }
}
NSDictionary *EzwinRuntimeStatus(void) {
    pthread_mutex_lock(&progressMutex);
    NSDictionary *progress = runtimeProgress;
    NSString *stage = gameplayStage;
    pthread_mutex_unlock(&progressMutex);
    @synchronized ((__bridge id)(void *)lockObject()) {
        NSDictionary *client=EzwinClientCallbackStatus();
        return @{@"installed":@(installed), @"tableWrites":@(tableWrites), @"skinSlots":@(skinWrites),
            @"backend":@"CoreEngine StaticInlineHook", @"stage":stage ?: startupStage,
            @"build":@"1.90.0-r15-source-clean", @"diagnosticLog":EzwinDiagnosticsPath(),
            @"unityUUID":observedUnityUUID, @"staticHooks":@(installed ? 5 + viewHookCount + fileProbeHookCount + ([client[@"active"] boolValue]?[client[@"installed"] unsignedIntValue]:0) : 0),
            @"fileProbeHooks":@(fileProbeHookCount),
            @"clientCallbacks":client,
            @"legacySerializerPackerMode":@"Legacy interior breakpoint addresses are not used by the traced current startup",
            @"viewHooks":@(viewHookCount),@"aimUpdates":progress[@"aimUpdates"] ?: @0,
            @"itemCount":progress[@"itemCount"] ?: @0,
            @"actorUpdates":progress[@"actorUpdates"] ?: @0, @"collectedActors":progress[@"collectedActors"] ?: @0,
            @"bindingAttempts":progress[@"bindingAttempts"] ?: @0, @"bindingsReady":progress[@"bindingsReady"] ?: @NO,
            @"cameraAvailable":progress[@"cameraAvailable"] ?: @NO, @"localActorAvailable":progress[@"localActorAvailable"] ?: @NO,
            @"menuOnly":@(EZWIN_MENU_ONLY != 0), @"nativeObjcHooksEnabled":@(EZWIN_ENABLE_NATIVE_OBJC_HOOKS != 0),
            @"skinKernelResult":@(skinHookResult),
            @"audioHooks":progress[@"audioHooks"] ?: @0,
            @"skinBinding":skinWrites == 2 ? @"static inline routes installed" : @"waiting for prepared Unity hook blocks",
            @"objc":objcStatus ?: @{},@"symbols":EzwinSymbolHookStatus(), @"target":@"Unity 1.90.0"};
    }
}

void EzwinRenderRuntimeWorldESP(const EzwinWorldESPPainter *painter, float delta) {
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    GameGuard guard; if (!guard.locked) return;
    {
        EzwinWorldESPOptions world = options.worldESP;
        world.arrows = world.arrows && options.esp.enabled;
        EzwinRenderWorldESP(&worldState, &collector, &world, painter, delta);
    }
}
