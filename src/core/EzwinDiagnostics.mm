#include "core/EzwinDiagnostics.h"
#include <TargetConditionals.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static uint64_t recorded[2];
static int logFile = -1;
static NSString *logPath;
static pthread_mutex_t logMutex = PTHREAD_MUTEX_INITIALIZER;

void EzwinStartDiagnostics(void) {
#if TARGET_OS_IOS
    pthread_mutex_lock(&logMutex);
    if (logFile < 0) {
        NSURL *directory = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
            inDomains:NSUserDomainMask].firstObject;
        logPath = [[directory URLByAppendingPathComponent:@"ezwin-runtime.log"] path];
        if (logPath) logFile = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (logFile >= 0) {
            off_t size = lseek(logFile, 0, SEEK_END);
            if (size > 131072) ftruncate(logFile, 0);
            const char session[] = "\nBuild 1.90.0-r15-source-clean: new session\n";
            write(logFile, session, sizeof(session) - 1);
        }
    }
    pthread_mutex_unlock(&logMutex);
#endif
}

void EzwinTraceCheckpoint(unsigned stage, const char *name) {
    if (stage >= 128 || !name) return;
    uint64_t bit = 1ULL << (stage%64);
    if (__atomic_fetch_or(recorded+stage/64, bit, __ATOMIC_RELAXED) & bit) return;
    pthread_mutex_lock(&logMutex);
    if (logFile >= 0) {
        char line[192];
        int count = snprintf(line, sizeof(line), "%02u %s [%s]\n", stage, name,
            [NSThread isMainThread] ? "main" : "worker");
        if (count > 0) write(logFile, line, (size_t)count < sizeof(line) ? (size_t)count : sizeof(line) - 1);
    }
    pthread_mutex_unlock(&logMutex);
}

NSString *EzwinDiagnosticsPath(void) { return logPath ?: @"Not available on this platform"; }
