#import "ui/EzwinSettings.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct SettingEntry {
    char *key;
    void *value;
    struct SettingEntry *next;
} SettingEntry;

static SettingEntry *gBoolSettings;
static SettingEntry *gFloatSettings;
static SettingEntry *gColorSettings;
static pthread_mutex_t gSettingsMutex = PTHREAD_MUTEX_INITIALIZER;

static void *FindSetting(SettingEntry **entries, NSString *key, size_t valueSize) {
    if (!key) return NULL;
    const char *name = key.UTF8String;
    if (!name) return NULL;

    pthread_mutex_lock(&gSettingsMutex);
    for (SettingEntry *entry = *entries; entry; entry = entry->next) {
        if (!strcmp(entry->key, name)) {
            void *value = entry->value;
            pthread_mutex_unlock(&gSettingsMutex);
            return value;
        }
    }

    SettingEntry *entry = (SettingEntry *)calloc(1, sizeof(SettingEntry));
    if (entry) {
        entry->key = strdup(name);
        entry->value = calloc(1, valueSize);
    }
    if (!entry || !entry->key || !entry->value) {
        if (entry) { free(entry->key); free(entry->value); free(entry); }
        pthread_mutex_unlock(&gSettingsMutex);
        @throw [NSException exceptionWithName:NSMallocException
            reason:@"Could not allocate a setting" userInfo:nil];
    }
    entry->next = *entries;
    *entries = entry;
    void *value = entry->value;
    pthread_mutex_unlock(&gSettingsMutex);
    return value;
}

bool *EzwinBoolSetting(NSString *key) {
    return (bool *)FindSetting(&gBoolSettings, key, sizeof(bool));
}

float *EzwinFloatSetting(NSString *key) {
    return (float *)FindSetting(&gFloatSettings, key, sizeof(float));
}

uint32_t *EzwinColorSetting(NSString *key) {
    return (uint32_t *)FindSetting(&gColorSettings, key, sizeof(uint32_t));
}
