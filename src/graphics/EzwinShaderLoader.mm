#include "unity/EzwinUnity.h"
#include <stdio.h>

static void *loadedBundle;
static NSString *bundlePath;

void *EzwinLoadShaderBundle(NSError **error) {
    if (!EzwinUnityBase()) return nullptr;
    if (EzwinUnityValid(loadedBundle)) return loadedBundle;
    NSData *data = EzwinShaderBundleData();
    if (!bundlePath) {
        NSURL *directory = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        bundlePath = [[directory URLByAppendingPathComponent:@"ezwin-readable-shaders.bundle"] path];
    }
    if (!bundlePath || ![data writeToFile:bundlePath options:NSDataWritingAtomic error:error]) return nullptr;
    void *load = EzwinUnityMethod("UnityEngine.AssetBundleModule.dll", "UnityEngine", "AssetBundle", "LoadFromFile", 1);
    if (load) loadedBundle = ((void *(*)(void *, void *))load)(EzwinUnityString(bundlePath.UTF8String), nullptr);
    if (!loadedBundle) {
        void *async = EzwinUnityMethod("UnityEngine.AssetBundleModule.dll", "UnityEngine", "AssetBundle", "LoadFromFileAsync", 1);
        void *result = EzwinUnityMethod("UnityEngine.AssetBundleModule.dll", "UnityEngine", "AssetBundleCreateRequest", "get_assetBundle", 0);
        if (async && result) {
            void *request = ((void *(*)(void *, void *))async)(EzwinUnityString(bundlePath.UTF8String), nullptr);
            if (request) loadedBundle = ((void *(*)(void *, void *))result)(request, nullptr);
        }
    }
    return loadedBundle;
}

void *EzwinLoadShader(void *bundle, const char *name) {
    if (!bundle || !name) return nullptr;
    void *getType = EzwinUnityMethod("mscorlib.dll", "System", "Type", "GetType", 1);
    void *load = EzwinUnityMethod("UnityEngine.AssetBundleModule.dll", "UnityEngine", "AssetBundle", "LoadAsset", 2);
    if (!getType || !load) return nullptr;
    void *type = ((void *(*)(void *, void *))getType)(EzwinUnityString("UnityEngine.Shader, UnityEngine.CoreModule"), nullptr);
    if (!type) return nullptr;
    NSString *asset = [NSString stringWithFormat:@"assets/%s.shader", name].lowercaseString;
    void *shader = ((void *(*)(void *, void *, void *, void *))load)(bundle, EzwinUnityString(asset.UTF8String), type, nullptr);
    return shader ? shader : ((void *(*)(void *, void *, void *, void *))load)(bundle, EzwinUnityString(name), type, nullptr);
}
