#include "unity/EzwinOffsets1900.h"
#include "unity/EzwinUnity.h"
#include <string.h>

static uintptr_t pointer(uintptr_t address) { uintptr_t value; memcpy(&value, (void *)address, 8); return value; }
static uint16_t shortAt(uintptr_t address) { uint16_t value; memcpy(&value, (void *)address, 2); return value; }
struct VirtualMethod { void *function, *info; };

static VirtualMethod *interfaceMethod(uintptr_t object, uintptr_t interface, int slot) {
    if (!object || !interface) return nullptr;
    uintptr_t type = pointer(object), offsets = pointer(type + EzwinField_TypeInterfaceOffsets);
    unsigned count = shortAt(type + EzwinField_TypeInterfaceCount);
    for (unsigned i = 0; i < count; ++i) {
        if (pointer(offsets + i * EzwinField_InterfaceEntryStride) != interface) continue;
        int offset; memcpy(&offset, (void *)(offsets + i * EzwinField_InterfaceEntryStride + EzwinField_InterfaceEntryOffset), 4);
        return (VirtualMethod *)(type + EzwinField_TypeVTable + (offset + slot) * EzwinField_VirtualMethodStride);
    }
    return ((VirtualMethod *(*)(uintptr_t, uintptr_t, int))(EzwinUnityBase() + EzwinUF_InterfaceFallback))(object, interface, slot);
}

int EzwinUnityWeaponID(uintptr_t actor) {
    uintptr_t base = EzwinUnityBase();
    if (!base || !actor) return 0;
    uintptr_t weapon = ((uintptr_t (*)(uintptr_t, void *))(base + EzwinUF_WeaponHandle))(actor, nullptr);
    uintptr_t registryType = pointer(base + EzwinSlot_WeaponRegistryType);
    uintptr_t lookupInfo = pointer(base + EzwinSlot_WeaponLookupMethod);
    if (!weapon || registryType <= base || registryType & 7 || lookupInfo <= base || lookupInfo & 7) return 0;
    uintptr_t fields = pointer(registryType + EzwinField_TypeStaticFields), registry = fields ? pointer(fields) : 0;
    if (!registry) return 0;
    VirtualMethod *method = interfaceMethod(registry, pointer(lookupInfo + EzwinField_MethodInfoInterface), shortAt(lookupInfo + EzwinField_MethodInfoSlot));
    if (!method || !method->info) return 0;
    uintptr_t inflated = ((uintptr_t (*)(void *, uintptr_t))(base + EzwinUF_GenericMethod))(method->info, lookupInfo);
    if (!inflated) return 0;
    void *invoke = (void *)pointer(inflated + EzwinField_MethodInvoker);
    uintptr_t handle = 0;
    if (!invoke || !((bool (*)(uintptr_t, uintptr_t, uintptr_t *, uintptr_t))invoke)
        (registry, weapon, &handle, inflated) || !handle) return 0;
    uintptr_t conversionInfo = pointer(base + EzwinSlot_WeaponConversionMethod);
    if (conversionInfo <= base || conversionInfo & 7) return 0;
    uintptr_t reference = 0;
    ((void (*)(uintptr_t, uintptr_t *, uintptr_t))(base + EzwinUF_ReferenceConversion))(handle, &reference, conversionInfo);
    if (!reference) return 0;
    // The new image resolves this definition getter by name instead of the old interface slot 0x15.
    void **definitionMethod = ((void **(*)(uintptr_t, const char *, int, int, int))(base + EzwinUF_MethodLookup))
        (pointer(reference), "OE47BE9298", 0, 0, 0);
    if (!definitionMethod || !*definitionMethod) return 0;
    uintptr_t definition = ((uintptr_t (*)(uintptr_t, void *))*definitionMethod)(reference, definitionMethod);
    int identifier = 0;
    if (definition) memcpy(&identifier, (void *)(definition + EzwinField_DefinitionIdentifier), 4);
    return identifier;
}
